pragma ton-solidity >= 0.51.0;

import "SyncFS.sol";
import "ICache.sol";
import "SharedCommandInfo.sol";

interface IPages {
    function query_pages() external view;
}

/* Base contract for the devices exporting command manuals */
contract ManualPages is SyncFS, IImport, SharedCommandInfo {

    Page[] public _pages;

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    uint16 constant CMD_INDEX_START = 30;

    function add_page(Page page) external accept {
//        _add_page(page);
        _stash_page(page);
    }

    function _stash_page(Page page) internal {
        _pages.push(page);
    }

    function process_pages(mapping (uint16 => Inode) inodes) external accept {
        for ((uint16 idx, Inode inode): inodes)
            _inodes[idx] = inode;
    }

    function view_pages() external view returns (Page[] pages) {
        return _pages;
    }

    function transform_pages(uint8 start, uint8 count) external view returns (mapping (uint16 => Inode) inodes) {
        uint cap = math.min(_pages.length, start + count);
        for (uint i = start; i < cap; i++) {
            Page page = _pages[i];
            (string command, string purpose, string synopsis, string description, string option_list,
                uint8 min_args, uint16 max_args, string[] option_descriptions) = page.unpack();
            Inode cmd_inode = _get_any_node(FT_REG_FILE, SUPER_USER, SUPER_USER_GROUP, command,
                [command, purpose, synopsis, description, option_list, _join_fields(option_descriptions, "\t"), format("{}\t{}", min_args, max_args)]);
            uint16 idx = _fetch_file_index(command, ROOT_DIR + 1);
            inodes[idx] = cmd_inode;
        }
    }

    function fetch_command_info() external view returns (string[] command_names, mapping (uint8 => CmdInfoS) command_info) {
        for (Page page: _pages) {
            (string command, , , , string option_list,
                uint8 min_args, uint16 max_args, ) = page.unpack();
            uint8 cmd_idx;
            uint16 dir_idx = _dir_index(command, ROOT_DIR + 1);
            if (dir_idx > 0)
                cmd_idx = uint8(dir_idx) - 1;
            command_names.push(command);
            if (cmd_idx > 0) {
                bytes opts = bytes(option_list);
                uint flags;
                for (uint i = 0; i < opts.length; i++)
                    flags |= uint(1) << uint8(opts[i]);
                command_info[cmd_idx] = CmdInfoS(min_args, max_args, flags);
            }
        }
    }

    function _add_page(Page page) internal {
        (string command, string purpose, string synopsis, string description, string option_list,
            uint8 min_args, uint16 max_args, string[] option_descriptions) = page.unpack();
        Inode cmd_inode = _get_any_node(FT_REG_FILE, SUPER_USER, SUPER_USER_GROUP, command,
                [command, purpose, synopsis, description, option_list, _join_fields(option_descriptions, "\t"), format("{}\t{}", min_args, max_args)]);

        uint16 dir_idx = _dir_index(command, ROOT_DIR + 1);
        uint16 idx = dir_idx > 0 ? _fetch_file_index(command, ROOT_DIR + 1) : _sb.inode_count++;
        _inodes[idx] = cmd_inode;
        string s_de = _dir_entry_line(idx, command, FT_REG_FILE);
        if (dir_idx > 0)
            _inodes[ROOT_DIR + 1].text_data[dir_idx - 1] = s_de;
        else
            _inodes[ROOT_DIR + 1].text_data.push(s_de);
        uint8 cmd_idx = _command_index(command);
        if (cmd_idx > 0) {
            bytes opts = bytes(option_list);
            uint flags;
            for (uint i = 0; i < opts.length; i++)
                flags |= uint(1) << uint8(opts[i]);
            _command_info[cmd_idx] = CmdInfoS(min_args, max_args, flags);
        }
    }

    function get_command_info() external view returns (string[] command_names, mapping (uint8 => CmdInfoS) command_info) {
        string[] commands = _get_file_contents("/etc/command_list");
        for (uint i = 0; i < commands.length; i++) {
            command_names.push(commands[i]);
            string[] command_data = _get_file_contents("/bin/" + commands[i]);
            uint len = command_data.length;
            if (len > 4) {
                string option_list = command_data[4];
                bytes opts = bytes(option_list);
                uint flags;
                for (uint j = 0; j < opts.length; j++)
                    flags |= uint(1) << uint8(opts[j]);
                if (len > 6) {
                    string s_n_args = command_data[6];
                    string[] min_max_args = _split(s_n_args, "\t");
                    (uint u_min_args, bool min_success) = stoi(min_max_args[0]);
                    (uint u_max_args, bool max_success) = stoi(min_max_args[1]);
                    if (min_success && max_success) {
                        command_info[uint8(i) + 1] = CmdInfoS(uint8(u_min_args), uint16(u_max_args), flags);
                    }
                }
            }
        }

    }
    /* Print an internal debugging information about the file system state */
    function dump_fs(uint8 level) external view returns (string) {
        return _dump_fs(level, _sb, _inodes);
    }

    function _init() internal override accept {
    }

    function init_fs(SuperBlock sb, mapping (uint16 => Inode) inodes) external accept {
        _sb = sb;
        _inodes = inodes;
    }

    function assign_pages(address[] pages) external pure accept {
        for (address addr: pages)
            IPages(addr).query_pages();
    }

    function update_node(Inode inode) external override accept {
        string file_name = inode.file_name;
        uint16 dir_idx = _dir_index(file_name, ROOT_DIR + 2);
        uint16 idx = dir_idx > 0 ? _fetch_file_index(file_name, ROOT_DIR + 2) : _sb.inode_count++;
        _inodes[idx] = inode;
        string s_de = _dir_entry_line(idx, file_name, FT_REG_FILE);
        if (dir_idx > 0)
            _inodes[ROOT_DIR + 2].text_data[dir_idx - 1] = s_de;
        else
            _inodes[ROOT_DIR + 2].text_data.push(s_de);
        if (file_name == "command_list") {
            _command_names = inode.text_data;
        }
    }

    function read_page(InputS input) external view returns (string out) {
        (uint8 c, string[] args, ) = input.unpack();

        /* informational commands */
        if (c == help) out = _help(args);
        if (c == man) out = _man(args);
        if (c == whatis) out = _whatis(args);
    }

    /* Informational commands */
    function _help(string[] args) private view returns (string out) {
        if (args.empty())
            return "Commands: " + _join_fields(_get_file_contents("/etc/command_list"), " ") + "\n";

        for (string s: args) {
            if (!_is_command_info_available(s)) {
                out.append("help: no help topics match" + _quote(s) + "\n");
            }
            out.append(_get_help_text(s));
        }
    }

    function _man(string[] args) private view returns (string out) {
        for (string s: args)
            out.append(_is_command_info_available(s) ? _get_man_text(s) : "No manual entry for " + s + "\n");
    }

    function _whatis(string[] args) private view returns (string out) {
        if (args.empty())
            return "whatis what?\n";

        for (string s: args) {
            if (_is_command_info_available(s)) {
                (string name, string purpose, , , , ) = _get_command_info(s);
                out.append(name + " (1)\t\t\t - " + purpose + "\n");
            } else
                out.append(s + ": nothing appropriate.\n");
        }
    }

    /* Imports helpers */
    function _get_imported_file_contents(string path, string file_name) internal view returns (string[] text) {
        uint16 dir_index = _resolve_absolute_path(path);
        (uint16 file_index, uint8 ft) = _fetch_dir_entry(file_name, dir_index);
        if (ft > FT_UNKNOWN)
            return _inodes[file_index].text_data;
        return ["Failed to read file " + file_name + " at path " + path + "\n"];
    }

    function _fetch_element(uint16 index, string path, string file_name) internal view returns (string) {
        if (index > 0) {
            string[] text = _get_imported_file_contents(path, file_name);
            return text.length > 1 ? text[index - 1] : _element_at(1, index, text, "\t");
        }
    }

    /* Informational commands helpers */
    function _get_man_text(string s) private view returns (string) {
        (string name, string purpose, string description, string[] uses, string option_names, string[] option_descriptions) = _get_command_info(s);
        string usage;
        for (string u: uses)
            usage.append("\t" + name + " " + u + "\n");
        string options;
        for (uint i = 0; i < option_descriptions.length; i++)
            options.append("\t" + "-" + option_names.substr(i, 1) + "\t" + option_descriptions[i] + "\n");
        options.append("\t" + "--help\tdisplay this help and exit\n\t--version\n\t\toutput version information and exit\n");

        return name + "(1)\t\t\t\t\tUser Commands\n\nNAME\n\t" + name + " - " + purpose + "\n\nSYNOPSIS\n" + usage +
            "\nDESCRIPTION\n\t" + description + "\n\n" + options;
    }

    function _get_help_text(string command) private view returns (string) {
        (string name, , string description, string[] uses, string option_names, string[] option_descriptions) = _get_command_info(command);
        string usage;
        for (string u: uses)
            usage.append("\t" + name + " " + u + "\n");
        string options = "\n";
        for (uint i = 0; i < option_descriptions.length; i++)
            options.append("  -" + option_names.substr(i, 1) + "\t\t" + option_descriptions[i] + "\n");
        options.append("  --help\tdisplay this help and exit\n  --version\toutput version information and exit\n");

        return "Usage: " + usage + description + options;
    }

    function _is_command_info_available(string command_name) private view returns (bool) {
        uint16 bin_dir_index = _get_file_index("/bin");
        (uint16 command_index, uint8 ft) = _fetch_dir_entry(command_name, bin_dir_index);
        return ft > FT_UNKNOWN && _inodes.exists(command_index);
    }

    function _get_command_info(string command) private view returns (string name, string purpose, string desc, string[] uses,
                string option_names, string[] option_descriptions) {
        string[] command_info = _get_imported_file_contents("/bin", command);
        return (command_info[0], command_info[1], _join_fields(_get_tsv(command_info[3]), "\n"),
            _get_tsv(command_info[2]), command_info[4], _get_tsv(command_info[5]));
    }
}
