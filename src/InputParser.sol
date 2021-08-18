pragma ton-solidity >= 0.48.0;

import "IOptions.sol";
import "IData.sol";
import "String.sol";
import "FSCache.sol";

contract InputParser is IOptions, FSCache {

    struct CmdInfoS {
        uint8 min_args;
        uint16 max_args;
        uint options;
    }
    mapping (uint8 => CmdInfoS) public _command_info;

    /* Primary entry point */
    function parse(SessionS i_ses, string s_input) external view returns (Std std, SessionS ses, InputS input, ReadEventS[] re, IOEventS[] ios, INodeEventS[] ines, uint16 action) {
        string out;
        string err;

        /* Validate session info: uid and wd */
        uint16 uid = _users.exists(i_ses.uid) ? i_ses.uid : REG_USER;
        uint16 gid = _ugroups.exists(i_ses.gid) ? i_ses.gid : _get_group_id(uid);
        uint16 wd = _inodes.exists(i_ses.wd) ? i_ses.wd : _users[uid].home_dir;
        ses = SessionS(uid, gid, wd);

        /* Parse input line */
        (uint8 c, string cmds, string[] args, uint flags, string ostr, string target) = _parse_input(s_input);
        if (c == 0) {
            err = cmds + ": command not found\n";
            input = InputS(c, args, flags, target);
        } else if (flags >= (1 << 254)) {
            if ((flags & 1 << 255) > 0)
                out = _get_help_text(cmds);
        } else {
            if (c == basename) out = _basename(args, flags);
            if (c == dirname) out = _dirname(args);
            if (c == uname) out = _uname(flags);
            if (c == help) (out, err) = _read_help_file(args);
            if (c == echo) out = _echo(flags, args);
            if (c == man)
                for (string s: args) {
                    string text = _get_man_text(s);
                    out.append(text.empty() ? "No manual entry for " + s + "\n" : text);
                }

            /* Push assumed arguments for certain commands */
            if (args.empty() && (c == du || c == ls || c == df))
                args.push(".");
            if (args.empty() && c == cd)
                args.push("~");

            /* Diagnose common errors early:
                - missing or extra operands
                - unknown options        */
            input = InputS(c, args, flags, target);
            CmdInfoS ci = _command_info[c];
            uint odiff = flags - (ci.options & flags);
            uint16 nargs = uint16(args.length);
            if (nargs < ci.min_args || nargs > ci.max_args || odiff > 0) {
                err.append(cmds + ": ");
                if (nargs < ci.min_args)
                    err.append("missing file operand");
                else if (nargs > ci.max_args)
                    err.append("extra operand" + _quote(args[ci.max_args]));
                else if (odiff > 0)
                    err.append("invalid option --" + _quote(ostr));
                err += "\nTry " + cmds + " --help for more information.\n";
            }
            if (_op_session(c)) {
                if (c == pwd) out = _pwd(flags, wd) + "\n";
                if (c == whoami) out = _users[uid].name + "\n";
                if (c == cd) {
                    (ses.wd, ) = _cd(flags, args[0], wd);
                    action |= CHANGE_DIR;
                }
            }
        }

        if (!target.empty()) action |= PIPE_OUT_TO_FILE;
        if (!err.empty()) action |= PRINT_ERROR;
        if (!out.empty()) action |= PRINT_OUT;
        if (!ios.empty()) action |= IO_EVENT;
        if (!re.empty()) action |= READ_EVENT;
        if (_op_stat(c)) action |= PRINT_STAT;
        if (_op_file(c) || _op_access(c) || _op_fs(c) || _op_network(c)) action |= PROCESS_COMMAND;

        std = Std(out, err);
    }

    function _read_help_file(string[] args) private view returns (string out, string err) {
        if (!args.empty()) {
            for (string s: args) {
                string help_text = _get_help_text(s);
                if (!help_text.empty())
                    out.append(help_text);
                else {
                    err.append("help: no help topics match" + _quote(s) + "\nTry" + _quote("help help") + "or" + _quote("man -k " + s) + "or" + _quote("info " + s) + "\n");
                    break;
                }
            }
        } else {
            out.append("Commands: ");
            for (string s: _command_names)
                out.append(s + " ");
            out.append("\n");
        }
    }

    /* Parser */
    function _parse_input(string s) private view returns (uint8 cmd, string cmds, string[] args, uint flags, string ostr, string target) {
        uint len = s.byteLength();
        uint pos;
        bool tgt_next;
        string lexem;
        (cmds, pos) = _parse_to_symbol(s, 0, len, " ");
        cmd = _match_command(cmds);
        if (cmd == 0)
            return (0, cmds, args, flags, ostr, target);
        while (pos < len) {
            pos++;
            (lexem, pos) = _parse_to_symbol(s, pos, len, s.substr(pos, 1) == "\"" ? "\"" : " ");
            uint l = lexem.byteLength();
            if (l == 0)
                break;
            if (lexem.substr(0, 1) == "-") {
                if (l > 1 && lexem.substr(1, 1) == "-") {
                    if (lexem == "--help") flags |= 1 << 255;
                    if (lexem == "--version") flags |= 1 << 254;
                } else {
                    bytes opts = bytes(lexem);
                    ostr += lexem.substr(1, lexem.byteLength() - 1);
                    for (uint i = 1; i < opts.length; i++)
                        flags |= uint(1) << uint8(opts[i]);
                }
            } else if (lexem.substr(0, 1) == ">") {
                if (l == 1)
                    tgt_next = true;
                else
                    target = lexem.substr(1, l - 1);
            } else if (tgt_next) {
                target = lexem;
                tgt_next = false;
            } else
                args.push(lexem);
        }
    }

    /* Commands */

    /* Session commands */
    function _cd(uint flags, string s, uint16 cwd) private view returns (uint16 wd, ErrS[] es) {
        if (((flags & _e + _P) > 0) && cwd < INODES)
            es.push(ErrS(1, 0, /*no_such_file_or_dir*/ENOENT, s));
        wd = cwd;
//        bool follow_symlinks = ((flags & _L) > 0) && ((flags & _P) == 0);
//        (uint16 di, ) = follow_symlinks ? _lookup_opnd_deref(s, wd, 1) : _lookup_inode_in_dir(s, wd);
        uint16 di = _lookup_inode_in_dir(s, wd);
        if (di < INODES)
            es.push(ErrS(1, 0, /*no_such_file_or_dir*/ENOENT, s));
        else
            wd = di;
    }

    function _get_abs_path(uint16 dir) internal view returns (string) {
        if (dir == ROOT_DIR)
            return "/";
        uint16 parent = _get_parent_dir(dir);
        string dir_name = _lookup_name(dir, _inodes[parent].text_data);
        return (parent == ROOT_DIR ? "" : _get_abs_path(parent)) + "/" + dir_name;
    }

    function _pwd(uint /*flags*/, uint16 wd) private view returns (string) {
//        bool follow_symlinks = ((flags & _L) > 0) && ((flags & _P) == 0);
        return _get_abs_path(wd);
    }

    function _basename(string[] args, uint flags) private pure returns (string out) {
        bool multiple_args = (flags & _a) > 0; // -a
//        bool remove_suffices = (flags & _s) > 0; // -s
        string line_terminator = ((flags & _z) > 0) ? "\x00" : "\n";
//        string suffix = remove_suffices ? args[0] : "";

        if (multiple_args)
            for (string s: args)
                out.append(_not_dir(s) + line_terminator);
        else
            out = _not_dir(args[0]) + line_terminator;
    }

    function _dirname(string[] args) internal pure returns (string out) {
        for (string s: args)
            out += _dir(s) + "\n";
    }

    function _uname(uint flags) private pure returns (string out) {
        if ((flags & _s) > 0 || flags == 0) out = "Tonix ";
        if ((flags & _n) > 0) out += "FileSys ";
        if ((flags & _i + _m) > 0) out += "TON ";
        if ((flags & _o) > 0) out.append("TON OS ");
        if ((flags & _p) > 0) out.append("TON ");
        if ((flags & _a) > 0) out = "Tonix FileSys TON TONOS TON";
        out.append("\n");
    }

    function _echo(uint flags, string[] ss) private pure returns (string out) {
        bool no_trailing_newline = (flags & _n) > 0;
        uint len = ss.length;
        if (len > 0) out = ss[0];
        for (uint i = 1; i < len; i++)
            out.append(" " + ss[i]);
        if (!no_trailing_newline)
            out.append("\n");
    }

    function _c1() private {
        uint _RHLP = _R + _H + _L + _P;
        uint _bfntTv = _b + _f + _n + _t + _T + _v;
        _insert(basename, 1, M, _a + _s + _z);
        _insert(cat,    1, M, _b + _e + _E + _n + _s + _t + _T + _u + _v);
        _insert(cd,     1, 1, _L + _P + _e);
        _insert(chgrp,  2, M, _c + _f + _v + _h + _RHLP);
        _insert(chmod,  2, M, _c + _f + _v + _R);
        _insert(chown,  2, M, _c + _f + _v + _h + _RHLP);
        _insert(cksum,  1, M, 0);
        _insert(cmp,    2, 2, _b + _i + _l + _n + _s + _v);
        _insert(cp,     2, M, _a + _d + _l + _p + _r + _s + _u + _x + _RHLP + _bfntTv);
        _insert(dd,     2, 2, 0);
        _insert(df,     1, M, _a + _B + _h + _H + _i + _k + _l + _P + _t + _T + _x + _v);
        _insert(dirname,1, M, _z);
        _insert(du,     1, 1, _a + _b + _c + _D + _h + _H + _k + _l + _L + _m + _P + _s + _S + _x + _0);
        _insert(echo,   1, M, _n);
        _insert(file,   1, M, _v + _b + _N + _0 + _E);
        _insert(help,   0, M, _d + _m);
        _insert(ln,     2, M, _r + _s + _L + _P + _bfntTv);
        _insert(ls,     1, M, _a + _A + _B + _c + _C + _d + _f + _F + _g + _G + _h + _H + _i + _k + _l + _L + _m + _n + _N +
            _o + _p + _q + _Q + _r + _R + _s + _S + _t + _u + _U + _v + _x + _1);
        _insert(man,    0, M, _a);
        _insert(mkdir,  1, M, _m + _p + _v);
        _insert(mv,     2, M, _u + _bfntTv);
        _insert(paste,  1, M, _s + _z);
        _insert(pwd,    0, 0, _L + _P);
        _insert(rm,     1, M, _f + _r + _R + _d + _v);
        _insert(rmdir,  1, M, _p + _v);
        _insert(stat,   1, M, _L + _f + _t);
        _insert(touch,  1, M, _a + _c + _m);
        _insert(uname,  0, 0, _a + _s + _n + _r + _v + _m + _p + _i + _o);
        _insert(wc,     1, M, _c + _m + _l + _L + _w);
        _insert(whoami, 0, 0, 0);
        _insert(mount,  0, 3, _a + _c + _f + _l + _n + _v + _w);
        _insert(ping,   1, 1, _D + _n + _q + _U + _v);
        _insert(account,1, 1, _D);
    }

    function _insert(uint8 index, uint8 min_args, uint16 max_args, uint options) private {
        _command_info[index] = CmdInfoS(min_args, max_args, options);
    }

    /* Helpers */

    function _parse_to_symbol(string s, uint start, uint len, string sym) private pure returns (string, uint pos) {
        pos = start;
        while (pos < len) {
            if (s.substr(pos, 1) == sym)
                return (s.substr(start, pos - start), pos);
            pos++;
        }
        return (pos > start ? s.substr(start, pos - start) : "", pos);
    }

    function _get_usr_share_dir() private view returns (uint16) {
        return _lookup_inode_in_dir("share", _lookup_inode_in_dir("usr", ROOT_DIR));
    }

    function _get_help_text(string s) private view returns (string text) {
        uint16 hf = _lookup_inode_in_dir(s, _lookup_inode_in_dir("help", _get_usr_share_dir()));
        if (hf > 0) {
            text = _inodes[hf].text_data;
            text.append(_get_options_text(s));
        }
    }

    function _get_man_text(string s) private view returns (string text) {
        uint16 mp = _lookup_inode_in_dir(s, _lookup_inode_in_dir("man", _get_usr_share_dir()));
        if (mp > 0) {
            text = _inodes[mp].text_data;
            text.append(_get_options_text(s));
        }
    }

    function _get_options_text(string s) private view returns (string) {
        uint16 ol = _lookup_inode_in_dir(s, _lookup_inode_in_dir("options", _get_usr_share_dir()));
        if (ol > 0)
            return _inodes[ol].text_data;
    }

    function init() external override accept {
        _init_commands();
        _init_errors();
        _sync_fs_cache();
        _c1();
    }

}
