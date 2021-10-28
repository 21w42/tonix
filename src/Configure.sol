pragma ton-solidity >= 0.51.0;

import "Format.sol";
import "Internal.sol";

/* Primary configuration files for a block device system initialization and error diagnostic data */
contract Configure is Format, Internal {

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    function _get_parent_offset(string parent, string[] file_list) internal pure returns (uint8 offset) {
        for (uint i = 0; i < file_list.length; i++)
            if (file_list[i] == parent)
                return uint8(i);
    }

    function split_line(string line, string separator) external pure returns (string[] fields) {
        return _split(line, separator);
    }

    function get_system_init(string config, string devices) external pure returns (mapping (uint8 => TextDataFile) config_files) {
        uint8 n = uint8(INODES) + 2;
        string[] file_list = ["/"];
        string[] config_lines = _split(config, "\n");
        string[] device_list = _split(devices, "\n");

        for (string line: config_lines) {
            string[] fields = _split(line, ":");
            uint n_fields = fields.length;
            string node_file_name = fields[0];
            uint8 node_type = _file_type(fields[1]);
            uint8 content_type = _file_type(fields[2]);
            uint8 node_index = _get_parent_offset(node_file_name, file_list) + uint8(ROOT_DIR);

            string[] contents;
            if (node_type == FT_DIR) {
                contents = _get_dots(node_index, ROOT_DIR);
                if (content_type == FT_REG_FILE || content_type == FT_DIR) {
                    string[] files = _split(fields[3], " ");
                    for (string file_name: files) {
                        file_list.push(file_name);
                        contents.push(_dir_entry_line(n, file_name, content_type));
                        if (content_type == FT_DIR)
                            config_files[n] = TextDataFile(content_type, file_name, _get_dots(n, node_index));
                        n++;
                    }
                } else if (content_type == FT_BLKDEV) {
                    for (string device_info: device_list) {
                        string[] dev_fields = _split(device_info, "\t");
                        if (dev_fields.length > 3) {
                            string file_name = dev_fields[2];
                            file_list.push(file_name);
                            contents.push(_dir_entry_line(n, file_name, content_type));
                            config_files[n++] = TextDataFile(content_type, file_name, [device_info]);
                        }
                    }
                }
            } else if (node_type == FT_REG_FILE) {
                if (content_type == FT_REG_FILE) {
                    if (n_fields > 4) {
                        string ifs = fields[3];
                        string ofs = fields[4];
                        bool translate = ifs != ofs;
                        bool split_fields = ofs.byteLength() == 2 && ofs.substr(0, 1) == "\\" && ofs.substr(1, 1) == "n";
                        for (uint i = 5; i < n_fields; i++) {
                            string s = fields[i];
                            if (translate) {
                                if (split_fields) {
                                    string[] subs = _split(s, ifs);
                                    for (string sub: subs)
                                        contents.push(sub);
                                } else
                                    contents.push(_translate(s, ifs, ofs));
                            } else
                                contents.push(s);
                        }
                    }
                } else if (content_type == FT_SOCK) {
                    if (node_file_name == "hosts") {
                        for (string device_info: device_list) {
                            string[] dev_fields = _split(device_info, "\t");
                            if (dev_fields.length > 5)
                                contents.push(format("{}\t{}", dev_fields[5], dev_fields[2]));
                        }
                    } else if (node_file_name == "hostname") {
                        string[] dev_fields = _split(device_list[BlockDevice_c - 1], "\t");
                        contents = [dev_fields[2], dev_fields[5]];
                    }
                }
            }
            config_files[node_index] = TextDataFile(node_type, node_file_name, contents);
        }
    }

    function _init() internal override {
    }

    function gen_init_data(string config) external pure returns (string status, mapping (uint16 => ProcessInfo) proc, mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups) {
        string[] config_lines = _split(config, "\n");

        for (string line: config_lines) {
            string[] fields = _split(line, ":");
            if (fields.length < 2)
                continue;
            string node_file_name = fields[0];
            uint8 content_type = _file_type(fields[1]);

            if (node_file_name == "group") {
                if (content_type == FT_SOCK) {
                    for (uint i = 2; i < fields.length; i++) {
                        string[] group_fields = _split(fields[i], " ");
                        if (group_fields.length < 2) {
                            status.append("insufficient records for group " + fields[i] + "\n");
                            continue;
                        }
                        string group_name = group_fields[0];
                        string group_id_s = group_fields[1];
                        (uint gid_u, bool success) = stoi(group_id_s);

                        if (success) {
                            uint16 gid = uint16(gid_u);
                            bool is_system_group = gid_u < REG_USER_GROUP;
                            groups[gid] = GroupInfo(group_name, is_system_group);
                        }
                    }
                }

            } else if (node_file_name == "passwd") {
                if (content_type == FT_SOCK) {
                    uint16 pid_count;
                    for (uint i = 2; i < fields.length; i++) {
                        string[] user_fields = _split(fields[i], " ");
                        if (user_fields.length < 5) {
                            status.append("insufficient records for user record " + fields[i] + "\n");
                            continue;
                        }
                        string user_name = user_fields[0];
                        string user_id_s = user_fields[1];
                        string group_id_s = user_fields[2];
                        string group_name = user_fields[3];
                        (uint uid_u, bool uid_success) = stoi(user_id_s);
                        (uint gid_u, bool gid_success) = stoi(group_id_s);

                        if (uid_success && gid_success) {
                            uint16 uid = uint16(uid_u);
                            uint16 gid = uint16(gid_u);
                            users[uid] = UserInfo(gid, user_name, group_name);
                            pid_count++;
                            proc[pid_count] = ProcessInfo(uid, pid_count, DEF_UMASK, ROOT);
                        }
                    }
                }
            }
        }
    }
}
