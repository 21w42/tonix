pragma ton-solidity >= 0.51.0;

import "CacheFS.sol";

contract FileManager is CacheFS {

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    /* Common file operations */
    function file_op(Session session, InputS input, Arg[] arg_list) external view returns (string out, IOEvent[] ios, uint16 action, Err[] errors) {
        uint16 wd = session.wd;
        (uint8 c, string[] args, uint flags) = input.unpack();

        /* Process related operations in separate subroutines */
        if (_op_access(c))
            (out, ios, errors) = _access_ops(c, args, flags, wd, arg_list);
        if (c == mkdir || c == touch || c == fallocate)
            (out, ios, errors) = _create_file_ops(c, flags, wd, arg_list);
        if (c == rm || c == rmdir)
            (out, ios, errors) = _remove_file_ops(c, flags, wd, arg_list);
        if (c == cp || c == mv || c == ln)
            (out, ios, errors) = _file_ops(c, args, flags, wd, arg_list);

        if (c == cmp) out = _cmp(flags, arg_list);

        if (!errors.empty()) action |= ACT_PRINT_ERRORS;
        if (!ios.empty()) action |= ACT_UPDATE_NODES;
    }

    /* File list operations (experimental) */
    function process_file_list(Session session, InputS input, string[] names, uint16[] indices) external pure returns (IOEvent[] ios, uint16 action, Err[] errors) {
        uint16 wd = session.wd;
        uint8 c = input.command;

        Arg[] args;
        for (uint i = 0; i < names.length; i++)
            args.push(Arg(names[i], FT_REG_FILE, indices[i], wd, 0));
        if (c == fallocate) ios = _fallocate(args, wd);
        if (c == truncate) ios = _truncate(args, wd);

        if (!errors.empty()) action |= ACT_PRINT_ERRORS;
        if (!ios.empty()) action |= ACT_UPDATE_NODES;
    }

    /* Access operations common routine */
    function _access_ops(uint8 c, string[] args, uint flags, uint16 wd, Arg[] arg_list) private view returns (string /*out*/, IOEvent[] ios, Err[] errors) {
        uint16 val = 0;
        string s0 = args[0];
        uint16[] indices;
        string[] paths;

        if (c == chgrp) {
            val = GUEST_USER_GROUP;
            for ((, UserInfo user_info): _users)
                if (user_info.primary_group == s0)
                    val = user_info.gid;
        } else if (c == chmod) {
            (uint val2, bool success) = stoi(s0);
            if (!success)
                errors.push(Err(invalid_mode, 0, s0));
            else
                val = uint16(val2);
        } else if (c == chown) {
            val = GUEST_USER;
            for ((uint16 uid, UserInfo user_info): _users)
                if (user_info.user_name == s0)
                    val = uid;
        }

        Arg[] args_out;
        for (Arg arg: arg_list) {
            (string s, uint8 ft, uint16 ino, , ) = arg.unpack();
            if (s == s0)
                continue;
            if (ino < INODES)
                errors.push(Err(0, ino, ""));
            else {
                (indices, paths, errors) = _process_access_op(c, flags, val, ino, ft);
                args_out.push(arg);
            }
        }
        if (!args_out.empty())
            ios.push(IOEvent(c == chmod ? IO_PERMISSION : IO_CHATTR, wd, args_out));
    }

    function _process_access_op(uint8 c, uint flags, uint16 val, uint16 ino, uint8 ft) private view returns (uint16[] indices, string[] paths, Err[] errors) {
        bool recursive = (flags & _R) > 0;
        /*bool traverse_arg = (flags & _H) > 0;
        bool traverse_all_symlinks = (flags & _L) > 0;
        bool do_not_traverse_symlinks = (flags & _P) > 0;*/
        if (ino < INODES) {
            errors.push(Err(0, ino, ""));
            return (indices, paths, errors);
        }

        if (!recursive || ft != FT_DIR)
            return (indices, paths, errors);

        string[] text_data = _inodes[ino].text_data;
        uint len = text_data.length;

        for (uint16 j = 3; j <= len; j++) {
            (, uint16 sub_index, uint8 sub_ft) = _read_dir_entry(text_data[j - 1]);
            (uint16[] sub_indices, string[] sub_paths, Err[] sub_errors) = _process_access_op(c, flags, val, sub_index, sub_ft);
            for (uint16 i: sub_indices)
                indices.push(i);
            for (string s: sub_paths)
                paths.push(s);
            for (Err e: sub_errors)
                errors.push(e);
        }
    }

    /* Create an empty file - mkdir and touch */
    function _create_file_ops(uint8 c, uint flags, uint16 wd, Arg[] arg_list) private pure returns (string out, IOEvent[] ios, Err[] errors) {
        bool md = c == mkdir;
        bool allocate = c == fallocate;
        bool create_files = md || (flags & _c) == 0;
        bool error_if_exists = md && (flags & _p) == 0;
        bool update_if_exists = !md && (flags & _m) == 0;
        bool report_actions = md && (flags & _v) > 0;

        uint8 event_type = md ? IO_MKDIR : allocate ? IO_ALLOCATE : IO_MKFILE;

        uint16 parent = wd;
        Arg[] args_create;
        Arg[] args_update;
        for (Arg arg: arg_list) {
            (string path, , , uint16 i_parent, uint16 dir_index) = arg.unpack();
            (, string s) = _dir(path);
            if (dir_index == 0) {
                arg.path = s;
                arg.ft = md ? FT_DIR : FT_REG_FILE;
                args_create.push(arg);
                parent = i_parent;
                if (report_actions)
                    out.append("mkdir: created directory" + _quote(s) + "\n");
            }
            else {
                if (error_if_exists)
                    errors.push(Err(0, EEXIST, s));
                if (update_if_exists)
                    args_update.push(arg);
            }
        }
        if (create_files && !args_create.empty())
            ios.push(IOEvent(event_type, parent, args_create));
        if (update_if_exists && !args_update.empty())
            ios.push(IOEvent(IO_UPDATE_TIME, parent, args_update));
    }

    /* Remove a file - rm and rmdir */
    function _remove_file_ops(uint8 c, uint flags, uint16 wd, Arg[] arg_list) private view returns (string out, IOEvent[] ios, Err[] errors) {
        bool verbose = (flags & _v) > 0;
        bool remove_empty_dirs = c == rmdir || (flags & _d) > 0;
        bool force_removal = (flags & _f) > 0;
//        bool recurse = (flags & _r) > 0;

        Arg[] args_out;
        for (Arg arg: arg_list) {
            (string s, uint8 ft, uint16 iop, , ) = arg.unpack();
            if (iop >= INODES) {
                Inode victim = _inodes[iop];
                if (ft == FT_DIR) {
                    if (remove_empty_dirs) {
                        if (victim.file_size <= 10) {
                            args_out.push(arg);
                            out = _if(out, verbose, "rmdir: removing directory," + _quote(s) + "\n");
                        } else
                            errors.push(Err(0, ENOTEMPTY, s));
                    } else
                        errors.push(Err(0, EISDIR, s));
                } else {
                    if (c == rm) {
                        args_out.push(arg);
                        out = _if(out, verbose, "removed" + _quote(s) + "\n");
                    } else
                        errors.push(Err(0, ENOTDIR, s));
                }
            } else
                if (!force_removal)
                    errors.push(Err(0, iop, s));
        }
        if (!args_out.empty())
            ios.push(IOEvent(IO_UNLINK, wd, args_out));
    }

    /* File manipulation operations - cp, ln and mv */
    function _file_ops(uint8 c, string[] args, uint flags, uint16 wd, Arg[] arg_list) private view returns (string out, IOEvent[] ios, Err[] errors) {
        bool verbose = (flags & _v) > 0;
        bool preserve = (flags & _n) > 0;
        bool request_backup = (flags & _b) > 0;
        bool to_file_flag = (flags & _T) > 0;
        bool to_dir_flag = (flags & _t) > 0;
        bool newer_only = (flags & _u) > 0;
        bool force = (flags & _f) > 0;
        bool recurse = (flags & _r + _R) > 0;
        bool hardlink = (c == cp) && ((flags & _l) > 0);
        bool symlink = (flags & _s) > 0;

        if (hardlink && symlink)
            errors.push(Err(hard_or_symlink, 0, ""));

        bool to_dir = to_dir_flag;
        uint nargs = args.length;
        bool multiple_sources = nargs > 2;

        uint last;
        uint first;
        uint target_n;

        if (to_dir_flag) {
            first = 1;
            last = nargs;
            target_n = 0;
        } else {
            first = 0;
            last = nargs - 1;
            target_n = nargs - 1;
        }
        Arg arg_target = arg_list[target_n];
        (string t_path, uint8 t_ft, uint16 t_ino, , ) = arg_target.unpack();
        bool dest_exists = t_ino >= INODES;

        if (dest_exists && c == ln && t_ft != FT_DIR) {
            if (multiple_sources)
                errors.push(Err(ln_target, ENOTDIR, t_path));
            else if (!force)
                errors.push(Err(symlink ? failed_symlink : failed_hardlink, EEXIST, t_path));
        }

        if (dest_exists && t_ft == FT_DIR)
            to_dir = true;

        bool collision = dest_exists && t_ft == FT_REG_FILE;
        bool overwrite_dest = collision && (!preserve || force);

        if (!errors.empty() || collision && preserve)
            return (out, ios, errors);

        if (request_backup && overwrite_dest) {
            out = _if(out, verbose, "(backup:" + _quote(t_path + "~") + ")");
            Arg arg_backup = arg_target;
            arg_backup.path.append("~");
            ios.push(IOEvent(IO_MKFILE, wd, [arg_backup]));
        }

        uint8 etype = 0;
        if (c == cp && !hardlink || c == mv && !to_dir)
            etype = IO_WR_COPY;
        if (c == ln && !symlink || c == cp && hardlink || c == mv && to_dir)
            etype = IO_HARDLINK;
        if (symlink)
            etype = IO_SYMLINK;

        Arg[] args_out;
        Arg[] args_unlink;

        if (etype == IO_SYMLINK)
            args_out.push(arg_target);

        for (uint i = first; i < last; i++) {
            Arg s_arg = arg_list[i];
            (string s_path, uint8 s_ft, uint16 s_ino, uint16 s_parent, uint16 s_dir_idx) = s_arg.unpack();

            if (s_ino < INODES) { errors.push(Err(0, s_ino, s_path)); break; }
            if (verbose) { out = _if(out, c == mv, "renamed"); out.append(_quote(s_path) + (c == ln ? "->" : "=>") + _quote(t_path)); }

            if (s_ft == FT_DIR && etype == IO_HARDLINK)
                errors.push(Err(no_hardlink_on_dir, 0, s_path));
            if (s_ft == FT_DIR && etype == IO_WR_COPY && !recurse)
                errors.push(Err(omitting_directory, 0, s_path));
            else if (to_file_flag && to_dir && s_ft == FT_REG_FILE)
                errors.push(Err(cant_overwrite_dir, 0, _quote(t_path)));
            else if (collision && newer_only) {
                if (_inodes[t_ino].modified_at > _inodes[s_ino].modified_at)
                    continue;
            } else {
                (, string file_name) = _dir(to_dir ? s_path : t_path);
                args_out.push(Arg(file_name, s_ft, s_ino, symlink ? s_parent : to_dir ? t_ino : wd, s_dir_idx));
                if (c == mv)
                    args_unlink.push(s_arg);
            }
        }
        if (!args_out.empty())
            ios.push(IOEvent(etype, to_dir ? t_ino : wd, args_out));
        if (overwrite_dest && errors.empty())
            args_unlink.push(arg_target);
        if (!args_unlink.empty()) {
            ios.push(IOEvent(IO_UNLINK, wd, args_unlink));
        }
    }

    /* File comparison - cmp. Does it belong here? */
    function _cmp(uint flags, Arg[] arg_list) private view returns (string out) {
        bool verbose = (flags & _l) > 0;
        bool print_bytes = (flags & _b) > 0;

        string[] t1 = _inodes[arg_list[0].idx].text_data;
        string[] t2 = _inodes[arg_list[1].idx].text_data;
        string file_name_1 = arg_list[0].path;
        string file_name_2 = arg_list[1].path;
        for (uint i = 0; i < t1.length; i++) {
            string line1 = t1[i];
            string line2 = t2[i];
            bytes b1 = bytes(line1);
            bytes b2 = bytes(line2);
            for (uint j = 0; j < line1.byteLength(); j++) {
                uint8 u1 = uint8(b1[j]);
                uint8 u2 = uint8(b2[j]);
                if (u1 != u2) {
                    if (!verbose)
                        return file_name_1 + " " + file_name_2 + " differ: byte " +
                            _if(format("{}, line {}", j + 1, i + 1), print_bytes, format(" is {} {}", u1, u2)) + "\n";
                    out.append(format("{:3} {:3} {:3}\n", j, u1, u2));
                }
            }
        }
    }

    /* Experimental */
    function _fallocate(Arg[] args, uint16 wd) private pure returns (IOEvent[] ios) {
        ios.push(IOEvent(IO_ALLOCATE, wd, args));
    }

    function _truncate(Arg[] args, uint16 wd) private pure returns (IOEvent[] ios) {
        ios.push(IOEvent(IO_TRUNCATE, wd, args));
    }

}
