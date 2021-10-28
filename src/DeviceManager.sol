pragma ton-solidity >= 0.51.0;

import "CacheFS.sol";

contract DeviceManager is CacheFS {

    uint8 _devc;
    MountInfo[] public _static_mounts;
    MountInfo[] public _current_mounts;
    DeviceInfo[] public _devices;

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    /* Query devices and file systems status */
    function dev_stat(Session session, InputS input, Arg[] arg_list) external view returns (string out, uint16 action, Err[] errors) {
        (uint8 c, string[] args, uint flags) = input.unpack();
        uint16 pid = session.pid;
        pid = pid;
        /* File system status */
        if (_op_dev_stat(c))
            (out, errors) = _dev_stat(c, flags, args, arg_list);  // 5.2

        if (!errors.empty())
            action |= ACT_PRINT_ERRORS;
    }

    /* Query devices and file systems status */
    function dev_admin(Session session, InputS input, Arg[] arg_list) external accept {
        (uint8 c, string[] args, uint flags) = input.unpack();
        uint16 pid = session.pid;
        if (!arg_list.empty())
            pid = pid;
        /* File system status */
        if (_op_dev_admin(c))
            _dev_admin(c, flags, args);  // 1k
    }

    function account_info(InputS input) external view returns (string[] host_names, address[] addresses) {  // 500
        (, string[] args, uint flags) = input.unpack();
        string[] text = _get_file_contents("/etc/hosts");
        if (!args.empty())
            for (string s: args) {
                if ((flags & _d) == 0) {
                    host_names.push(s);
                    addresses.push(_to_address(_lookup_pair_value(s, text)));
                }
            }
        else
            for (string s: text) {
                string[] fields = _get_tsv(s);
                host_names.push(fields[1]);
                addresses.push(_to_address(fields[0]));
            }
    }

    function _dev_stat(uint8 c, uint flags, string[] args, Arg[] arg_list) private view returns (string out, Err[] errors) {
        if (c == df) out = _df(flags);      // 1k
        if (c == findmnt) out = _findmnt(flags, args);// 1k
        if (c == lsblk) (out, errors) = _lsblk(flags, args);// 1800
        if (c == mountpoint) (out, errors) = _mountpoint(flags, args, arg_list);// 500
        if (c == ps) out = _ps(flags); //400
    }

    function _dev_admin(uint8 c, uint flags, string[] args) private returns (string out) {
        if (c == losetup) out.append(_losetup(flags, args));      // 0
        if (c == mknod) out.append(_mknod(flags, args));// 0
        if (c == mount) _mount(flags, args);// 200
        if (c == udevadm) out.append(_udevadm(flags, args)); //0
        if (c == umount) out.append(_umount(flags, args));// 300
    }

    function _umount(uint flags, string[] args) private returns (string/* out*/) {
        bool unmount_all = (flags & _a) > 0;

        string s_source;
        string s_target;
        if (!args.empty()) {
            s_source = args[0];
            if (args.length > 1)
                s_target = args[1];
        }

        if (unmount_all) {
            for (MountInfo mnt: _current_mounts)
                _try_unmount(mnt);
        } else {
            uint8 index = _device_index(s_source);
            if (index > 0)
                _try_unmount(MountInfo(_devices[index - 1].minor_id, 1, _resolve_absolute_path(s_target), s_target, MOUNT_DIR));
        }
    }

    function _losetup(uint flags, string[] args) private view returns (string out) {
    }

    function _mount(uint flags, string[] args) private {
        bool mount_all = (flags & _a) > 0;
//        bool canonicalize_paths = (flags & _c) == 0;
//        bool dry_run = (flags & _f) > 0;
//        bool show_labels = (flags & _l) > 0;
//        bool no_mtab = (flags & _n) > 0;
//        bool verbose = (flags & _v) > 0;
//        bool read_write = (flags & _w) > 0;
//        bool alt_fstab = (flags & _T) > 0;
//        bool read_only = (flags & _r) > 0;
//        bool another_namespace = (flags & _N) > 0;
//        bool bind_subtree = (flags & _B) > 0;
//        bool move_subtree = (flags & _M) > 0;

        string s_source;
        string s_target;
        if (!args.empty()) {
            s_source = args[0];
            if (args.length > 1)
                s_target = args[1];
        }

        if (mount_all) {
            for (MountInfo mnt: _static_mounts)
                _try_mount(mnt);
        } else {
            uint8 index = _device_index(s_source);
            if (index > 0) {
                MountInfo mnt = MountInfo(_devices[index - 1].minor_id, 1, _resolve_absolute_path(s_target) - ROOT_DIR, s_target, MOUNT_DIR);
                if (_try_mount(mnt))
                    _current_mounts.push(mnt);
            }
        }
    }

    function _udevadm(uint flags, string[] args) private view returns (string out) {
    }

    function _mknod(uint flags, string[] args) private view returns (string out) {
    }
    /********************** File system and device status query *************************/
    function _df(uint flags) private view returns (string out) {
        (, , , uint16 inode_count, uint16 block_count, uint16 free_inodes, uint16 free_blocks, ,
        , , , , , , uint16 first_inode, ) = _sb.unpack();

        bool human_readable = (flags & _h) > 0;
        bool powers_of_1000 = (flags & _H) > 0;
        bool list_inodes = (flags & _i) > 0;
        bool block_1k = (flags & _k) > 0;
        bool posix_output = (flags & _P) > 0;

        string fs_name = _dev.name;
        Column[] columns_format = [
            Column(true, 20, ALIGN_LEFT),
            Column(true, 11, ALIGN_RIGHT),
            Column(true, 6, ALIGN_RIGHT),
            Column(true, 9, ALIGN_RIGHT),
            Column(true, 9, ALIGN_RIGHT),
            Column(true, 15, ALIGN_LEFT)];

        string s_units;
        string s_used;
        string s_avl;
        string s_p_used;
        uint u_used = list_inodes ? (inode_count - first_inode) : block_count;
        uint u_avl = list_inodes ? free_inodes : free_blocks;
        uint u_units = u_used + u_avl;
        uint u_p_used = u_used * 100 / u_units;

        if (list_inodes) {
            s_units = "Inodes";
            s_used = "IUsed";
            s_avl = "IFree";
            s_p_used = "IUse%";
        } else if (human_readable || block_1k) {
            s_units = "Size";
            s_used = "Used";
            s_avl = "Avail";
            s_p_used = "Use%";
        } else if (posix_output || powers_of_1000) {
            s_units = "1024-blocks";
            s_used = "Used";
            s_avl = "Available";
            s_p_used = "Capacity%";
        } else {
            s_units = "1K-blocks";
            s_used = "Used";
            s_avl = "Available";
            s_p_used = "Use%";
        }

        string[] header = ["Filesystem", s_units, s_used, s_avl, s_p_used, "Mounted on"];
        string[] row0 = [
                fs_name,
                format("{}", u_units),
                format("{}", u_used),
                format("{}", u_avl),
                format("{}%", u_p_used),
                "/"];

        out = _format_table_ext(columns_format, [header, row0], " ", "\n");
    }

    function _findmnt(uint flags, string[] /*args*/) private view returns (string out) {
        bool flag_fstab_only = (flags & _s) > 0;
        bool flag_mtab_only = (flags & _m) > 0;
        bool flag_kernel = (flags & _k) > 0;
        bool like_df = (flags & _D) > 0;
        bool first_fs_only = (flags & _f) > 0;
        bool no_headings = (flags & _n) > 0;
        bool no_truncate = (flags & _u) > 0;
        bool all_columns = (flags & _o) > 0;

        bool df_style = like_df || all_columns;
        bool non_df_style = !like_df || all_columns;

        MountInfo[] mnt_list = flag_fstab_only ? _static_mounts : _current_mounts;

        if (!flag_mtab_only || flag_kernel)
            for (MountInfo mnt: _static_mounts)
                for (MountInfo m: _current_mounts)
                    if (!_compare_mount_info(m, mnt))
                        mnt_list.push(mnt);

        string[][] table;

        uint target_path_width = no_truncate ? 70 : 30;
        uint source_width = no_truncate ? 70 : 20;

        Column[] columns_format = [
            Column(non_df_style, target_path_width, ALIGN_LEFT),
            Column(true, source_width, ALIGN_LEFT),
            Column(true, 6, ALIGN_LEFT),
            Column(non_df_style, target_path_width, ALIGN_LEFT),
            Column(df_style, 6, ALIGN_RIGHT),
            Column(df_style, 6, ALIGN_RIGHT),
            Column(df_style, 6, ALIGN_RIGHT),
            Column(df_style, 4, ALIGN_RIGHT),
            Column(df_style, target_path_width, ALIGN_LEFT)];

        if (!no_headings)
            table = [["TARGET", "SOURCE", "FSTYPE", "OPTIONS", "SIZE", "USED", "AVAIL", "USE%", "TARGET"]];

        (, , , , uint16 block_count, , uint16 free_blocks, ,
        , , , , , , , ) = _sb.unpack();

        uint u_used = block_count;
        uint u_avl = free_blocks;
        uint u_units = u_used + u_avl;
        uint u_p_used = u_used * 100 / u_units;

        for (MountInfo mnt: mnt_list) {
            (uint8 source_dev_id, uint16 source_export_id, , string target_path, uint16 options) = mnt.unpack();
            table.push([
                target_path,
                _devices[source_dev_id - 1].name,
                format("{}", source_export_id),
                format("{}", options),
                format("{}", u_units),
                format("{}", u_used),
                format("{}", u_avl),
                format("{}%", u_p_used),
                target_path]);
            if (first_fs_only)
                break;
        }

        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    function _mountpoint(uint flags, string[] args, Arg[] arg_list) private view returns (string out, Err[] errors) {
        bool mounted_device = (flags & _d) > 0;
        bool quiet = (flags & _q) > 0;
        bool arg_device = (flags & _x) > 0;

        string arg = args[0];
        Arg x_arg = arg_list[0];
        (string path, uint8 ft, uint16 index, , ) = x_arg.unpack();

        if (arg_device) {
            if (ft != FT_BLKDEV)
                errors = [Err(not_a_block_device, 0, path)];
            else {
                (string major_id, string minor_id) = _get_device_version(_inodes[index].text_data);
                out = major_id + ":" + minor_id;
            }
        }

        for (MountInfo m: _current_mounts) {
            (uint8 source_dev_id, , , string target_path,) = m.unpack();
            if (target_path == arg)
                out.append(mounted_device ? format("{}:{}", FT_BLKDEV, source_dev_id) : (path + " is a mountpoint"));
        }

        _if(out, out.empty(), path + " is not a mountpoint");
        if (quiet)
            out = "";
    }

    function _lsblk(uint flags, string[] args) private view returns (string out, Err[] errors) {
//        bool print_all_devices = (flags & _a) > 0;
        bool human_readable = (flags & _b) == 0;
        bool print_header = (flags & _n) == 0;
        bool print_fsinfo = (flags & _f) > 0;
        bool print_permissions = (flags & _m) > 0;
        bool print_device_info = !print_fsinfo && !print_permissions;
        bool full_path = (flags & _p) > 0;

        string[][] table;
        Column[] columns_format = [
            Column(true, 15, ALIGN_LEFT), // Name
            Column(print_device_info, 3, ALIGN_RIGHT),
            Column(print_device_info, 4, ALIGN_LEFT),
            Column(print_device_info || print_permissions, 7, ALIGN_CENTER),
            Column(print_device_info, 2, ALIGN_CENTER),
            Column(print_device_info, 4, ALIGN_CENTER),
            Column(print_fsinfo, 8, ALIGN_CENTER),
            Column(print_fsinfo, 6, ALIGN_CENTER),
            Column(print_device_info || print_fsinfo, 10, ALIGN_LEFT),
            Column(print_permissions, 5, ALIGN_CENTER),
            Column(print_permissions, 5, ALIGN_CENTER),
            Column(print_permissions, 10, ALIGN_LEFT)];

        uint16 dev_dir = _resolve_absolute_path("/dev");

        string[] header = ["NAME", "MAJ", ":MIN", "SIZE", "RM", "TYPE", "FSAVAIL", "FSUSE%", "MOUNTPOINT", "OWNER", "GROUP", "MODE"];

        if (print_header)
            table = [header];
        if (args.empty())
            for (DeviceInfo di: _devices)
                args.push(di.name);

        (, , , , uint16 block_count, , uint16 free_blocks, uint16 block_size, , , , , , , , ) = _sb.unpack();

        for (string s: args) {
            (uint16 dev_file_index, uint8 dev_file_ft) = _fetch_dir_entry(s, dev_dir);
            if (dev_file_ft == FT_BLKDEV || dev_file_ft == FT_CHRDEV) {
                (uint16 mode, uint16 owner_id, , , , , , , string[] lines) = _inodes[dev_file_index].unpack();
                string[] fields0 = _get_tsv(lines[0]);
                if (fields0.length < 4)
                    continue;
                string name = (full_path ? "/dev/" : "") + fields0[2];
                string mount_path = dev_file_ft == FT_BLKDEV ? ROOT : "";
                (, string s_owner, string s_group) = _users[owner_id].unpack();
                table.push([
                    name,
                    format("{}", fields0[0]),
                    format(":{}", fields0[1]),
                    _scale(uint32(block_count) * block_size, human_readable ? 1024 : 1),
                    "0",
                    "disk",
                    _scale(uint32(free_blocks) * block_size, human_readable ? 1024 : 1),
                    format("{}%", uint32(block_count) * 100 / (block_count + free_blocks)),
                    mount_path,
                    s_owner,
                    s_group,
                    _permissions(mode)]);
            } else
                errors.push(Err(not_a_block_device, 0, s));
        }
        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    /* Does not really belong here */
    function _ps(uint flags) internal view returns (string out) {
        bool format_full = (flags & _f) > 0;
        bool format_extra_full = (flags & _F) > 0;
        string[][] table = [["UID", "PID", "PPID", "CWD"]];
        Column[] columns_format = [
            Column(true, 5, ALIGN_LEFT),
            Column(true, 5, ALIGN_LEFT),
            Column(format_full || format_extra_full, 7, ALIGN_CENTER),
            Column(format_extra_full, 32, ALIGN_LEFT)];

        for ((uint16 pid, ProcessInfo proc): _proc) {
            (uint16 owner_id, uint16 self_id, , , string cwd) = proc.unpack();
            table.push([
                format("{}", owner_id),
                format("{}", pid),
                format("{}", self_id),
                cwd]);
        }
        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    /* mount helpers */
    function _compare_mount_info(MountInfo mnt_1, MountInfo mnt_2) internal pure returns (bool) {
        (uint8 src_dev_id_1, , uint16 target_mount_point_1, , ) = mnt_1.unpack();
        (uint8 src_dev_id_2, , uint16 target_mount_point_2, , ) = mnt_2.unpack();
        return (src_dev_id_1 == src_dev_id_2 && target_mount_point_1 == target_mount_point_2);
    }

    function _try_mount(MountInfo mnt) internal view returns (bool) {
        (uint8 source_dev_id, , uint16 target_mount_point, , uint16 options) = mnt.unpack();
        for (MountInfo m: _current_mounts)
            if (_compare_mount_info(m, mnt))
                return false;

        address source_address;
        for (DeviceInfo di: _devices) {
            (uint8 major_id, uint8 minor_id, , , , address device_address) = di.unpack();
            if (major_id == FT_BLKDEV && minor_id == source_dev_id)
                source_address = device_address;
        }
        if (!source_address.isStdZero()) {
            ISourceFS(_source).request_mount{value: 0.1 ton}(source_address, target_mount_point, options);
            return true;
        }
        return false;
    }

    function _try_unmount(MountInfo mnt) internal returns (bool) {
        for (uint16 i = 0; i < _current_mounts.length; i++)
            if (_compare_mount_info(_current_mounts[i], mnt)) {
                _current_mounts[i] = MountInfo(0, 0, 0, "", MOUNT_NONE);
                return true;
            }
        return false;
    }

    /* Device helpers */
    function _device_index(string name) internal view returns (uint8 index) {
        for (uint8 i = 0; i < _devices.length; i++)
            if (_devices[i].name == name)
                return i + 1;
    }

    function init_devices(DeviceInfo[] devices) external accept {
        _devices = devices;
        _devc = uint8(devices.length);
    }
}

