pragma ton-solidity >= 0.51.0;

import "Internal.sol";

/* Primary configuration files for a block device system initialization and error diagnostic data */
contract BuildFileSys is Internal {

    uint16 constant DEF_BLOCK_SIZE = 1024;
    uint16 constant DEF_BIN_BLOCK_SIZE = 4096;
    uint16 constant MAX_MOUNT_COUNT = 1024;
    uint16 constant DEF_INODE_SIZE = 128;
    uint16 constant MAX_BLOCKS = 400;
    uint16 constant MAX_INODES = 600;

    SuperBlock _sysfs_sb;
    mapping (uint16 => Inode) _sysfs_inodes;

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    function build_with_config(mapping (uint8 => TextDataFile) config_files) external pure returns (SuperBlock sb, mapping (uint16 => Inode) inodes) {
        return _init_with_system_config(config_files);
    }

    function init_with_system_config(mapping (uint8 => TextDataFile) config_files) external accept {
        (_sysfs_sb, _sysfs_inodes) = _init_with_system_config(config_files);
    }

    function _init_with_system_config(mapping (uint8 => TextDataFile) config_files) internal pure returns (SuperBlock sb, mapping (uint16 => Inode) inodes) {
        inodes[ROOT_DIR] = _get_dir_node(ROOT_DIR, ROOT_DIR, SUPER_USER, SUPER_USER_GROUP, "");
        uint16 node_count = ROOT_DIR + 1;

        for ((uint8 node_index, TextDataFile data_file): config_files) {
            (uint8 file_type, string file_name, string[] contents) = data_file.unpack();
            inodes[node_index] = _get_any_node(file_type, SUPER_USER, SUPER_USER_GROUP, file_name, contents);
            node_count++;
        }

        sb = SuperBlock(
            true, true, "sysfs", node_count, node_count - ROOT_DIR, MAX_INODES - node_count, MAX_BLOCKS + ROOT_DIR - node_count, DEF_BLOCK_SIZE,
            now, now, now, 0, MAX_MOUNT_COUNT, 1, ROOT_DIR, DEF_INODE_SIZE);
    }

    function dump_bfs() external view returns (string out) {
        return _dump_bfs(2, _sysfs_sb, _sysfs_inodes);
    }

    function _dump_bfs(uint8 /*level*/, SuperBlock sb, mapping (uint16 => Inode) inodes) internal pure returns (string out) {
        (bool file_system_state, bool errors_behavior, string file_system_OS_type, uint16 inode_count, uint16 block_count, uint16 free_inodes,
            uint16 free_blocks, uint16 block_size, uint32 created_at, uint32 last_mount_time, uint32 last_write_time, uint16 mount_count,
            uint16 max_mount_count, uint16 lifetime_writes, uint16 first_inode, uint16 inode_size) = sb.unpack();
        out = format("{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}\n",
            file_system_state ? "Y" : "N", errors_behavior ? "Y" : "N", file_system_OS_type, inode_count, block_count, free_inodes,
            free_blocks, block_size, created_at, last_mount_time, last_write_time, mount_count,
            max_mount_count, lifetime_writes, first_inode, inode_size);

        for ((uint16 i, Inode ino): inodes) {
            (uint16 mode, uint16 owner_id, uint16 group_id, uint32 file_size, uint16 n_links, uint32 modified_at, uint32 last_modified, string file_name, string[] text_data) = ino.unpack();
            out.append(format("{} {} {} {} {} {} {} {} {}\n", i, mode, owner_id, group_id, file_size, n_links, modified_at, last_modified, file_name));
                for (string s: text_data)
                    out.append(s + "\n");
        }
    }

    function _init() internal override {
    }

}
