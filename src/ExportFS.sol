pragma ton-solidity >= 0.51.0;

import "Internal.sol";
import "Commands.sol";
import "ICache.sol";

/* Base contract for the file system exporting devices */
abstract contract ExportFS is Internal, Commands, IExportFS {

    SuperBlock _export_sb;
    mapping (uint16 => Inode) _export_inodes;

    function _init_exports() internal virtual;

    function _init() internal override {
        _init_exports();
    }

    function init_fs(SuperBlock sb, mapping (uint16 => Inode) inodes) external override accept {
        _export_sb = sb;
        _export_inodes = inodes;
        _init_exports();
    }

    function _add_data_file(uint8 offset, string file_name, string[] contents) internal {
        uint16 counter = _export_sb.inode_count++;
        _export_inodes[counter] = _get_any_node(FT_REG_FILE, SUPER_USER, SUPER_USER_GROUP, file_name, contents);
        _export_inodes[ROOT_DIR + offset] = _add_dir_entry(_export_inodes[ROOT_DIR + offset], counter, file_name, FT_REG_FILE);
    }

    /* Respond to a request to export a set of index nodes to the specified mount point directory at the primary file system */
    function rpc_mountd(uint16 mount_point) external override accept {
        ISourceFS(msg.sender).mount_dir{value: 0.1 ton, flag: 1}(mount_point, _export_sb, _export_inodes);
        _export_sb.mount_count++;
        _export_sb.last_mount_time = now;
    }

    function query_export_node(string s_file_name) external override accept {
        SuperBlock sb = _export_sb;
        for (uint16 i = sb.first_inode; i < sb.inode_count; i++)
            if (_export_inodes[i].file_name == s_file_name) {
                IImport(msg.sender).update_node{value: 0.02 ton, flag: 1}(_export_inodes[i]);
                break;
            }
    }

    /* Print an internal debugging information about the exported file system state */
    function dump_export_fs(uint8 level) external view returns (string) {
        return _dump_fs(level, _export_sb, _export_inodes);
    }

}


