pragma ton-solidity >= 0.51.0;

import "IBootManager.sol";
import "SharedCommandInfo.sol";
import "ICache.sol";

struct DeviceRecord {
    uint8 major_version;
    uint8 minor_version;
    uint8 status;
    uint32 assembly_time;
    address location;
}

interface IDeviceManager {
    function init_devices(DeviceInfo[] devices) external;
}

interface IBlockDevice {
    function assign_readers(address[] readers) external;
    function update_fs_cache(SuperBlock sb, mapping (uint16 => ProcessInfo) processes, mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups, mapping (uint16 => Inode) inodes) external;
}

interface IManualPages {
    function init_fs(SuperBlock sb, mapping (uint16 => Inode) inodes) external;
    function assign_pages(address[] pages) external pure;
}

interface IAccessManager {
    function update_tables(mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups,
        uint16 reg_u, uint16 sys_u, uint16 reg_g, uint16 sys_g) external;
}

contract BootManager is Internal, IBootManager {

    uint16 constant DEF_BLOCK_SIZE = 1024;
    uint16 constant DEF_BIN_BLOCK_SIZE = 4096;
    uint16 constant MAX_MOUNT_COUNT = 1024;
    uint16 constant DEF_INODE_SIZE = 128;
    uint16 constant MAX_BLOCKS = 400;
    uint16 constant MAX_INODES = 600;

    mapping (uint8 => address) public _system;
    mapping (uint8 => DeviceInfo) _multi;

    SuperBlock _sysfs_sb;
    mapping (uint16 => Inode) _sysfs_inodes;

    mapping (uint8 => DeviceImage) public _images;
    DeviceRecord[] public _roster;
    uint32 public _counter = 90;
    bool public _live_update = false;

    constructor(DeviceInfo dev, address source) Internal (dev, source) public {
        _dev = dev;
        _source = source;
    }

    function get_system_data() external view returns (mapping (uint8 => address) system, mapping (uint8 => string) device_names) {
        system = _system;
        for ((uint8 i, DeviceImage dev): _images)
            device_names[i] = dev.description;
    }

    function get_system_devices() external view returns (string devices) {
        for ((, DeviceInfo dev): _multi) {
            (uint8 major_id, uint8 minor_id, string name, uint16 block_size, uint16 n_blocks, address device_address) = dev.unpack();
            devices.append(format("{}\t{}\t{}\t{}\t{}\t{}\n", major_id, minor_id, name, block_size, n_blocks, device_address));
        }
    }

    function set_counter(uint32 n) external accept {
        _counter = n;
    }

    function set_live_update(bool flag) external accept {
        _live_update = flag;
    }

    function apply_image(SuperBlock sb, mapping (uint16 => Inode) inodes) external view accept {
        _init_block_device(sb, inodes);
    }

    function set_manuals(SuperBlock sb, mapping (uint16 => Inode) inodes) external view accept {
        IManualPages(_system[ManualPages_c]).init_fs{value: 1 ton, flag: 1}(sb, inodes);
        _assign_pages();
    }

    function do_act(uint8 act, uint8[] actors) external view accept {
        if (act == 3)
            for (uint8 actor: actors)
                Base(_system[actor]).upgrade{value: 0.1 ton, flag: 1}(_images[actor].model);
        if (act == 4)
            for (uint8 actor: actors)
                Base(_system[actor]).reset_storage();
    }

    function _init_block_device(SuperBlock sb, mapping (uint16 => Inode) inodes) internal view {
        address bdev_addr = _system[BlockDevice_c];
        (mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups, mapping (uint16 => ProcessInfo) proc) = _get_init_user_data();
        IBlockDevice(bdev_addr).update_fs_cache{value: 1 ton, flag: 1}(sb, proc, users, groups, inodes);
    }

    function _get_init_user_data() internal pure returns (mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups, mapping (uint16 => ProcessInfo) proc) {
        proc[SUPER_USER + 1] = ProcessInfo(SUPER_USER, SUPER_USER + 1, DEF_UMASK, ROOT);
        proc[SUPER_USER + 2] = ProcessInfo(REG_USER, SUPER_USER + 2, DEF_UMASK, ROOT);
        proc[SUPER_USER + 3] = ProcessInfo(REG_USER + 1, SUPER_USER + 3, DEF_UMASK, ROOT);
        users[SUPER_USER] = UserInfo(SUPER_USER_GROUP, "root", "root");
        users[REG_USER] = UserInfo(REG_USER_GROUP, "boris", "staff");
        users[REG_USER + 1] = UserInfo(REG_USER_GROUP, "ivan", "staff");
        users[GUEST_USER] = UserInfo(GUEST_USER_GROUP, "guest", "guest");
        groups[SUPER_USER_GROUP] = GroupInfo("root", true);
        groups[REG_USER_GROUP] = GroupInfo("staff", false);
        groups[GUEST_USER_GROUP] = GroupInfo("guest", false);
    }

    function _init_access_data() internal view returns (mapping (uint16 => UserInfo) users, mapping (uint16 => GroupInfo) groups,
                    uint16 reg_u, uint16 sys_u, uint16 reg_g, uint16 sys_g) {
        (users, groups, ) = _get_init_user_data();
        for ((uint16 uid, ): users)
            if (uid < REG_USER)
                sys_u++;
            else
                reg_u++;
        for ((uint16 gid, ): groups)
            if (gid < REG_USER_GROUP)
                sys_g++;
            else
                reg_g++;
        IAccessManager(_system[AccessManager_c]).update_tables{value: 0.1 ton, flag: 1}(users, groups, sys_u, reg_u, sys_g, reg_g);
    }

    function _assign_readers() internal view {
        IBlockDevice(_system[BlockDevice_c]).assign_readers{value: 0.1 ton, flag: 1}(
            [_system[FileManager_c], _system[StatusReader_c], _system[PrintFormatted_c], _system[SessionManager_c], _system[DeviceManager_c]]);
    }

    function _assign_pages() internal view {
        IManualPages(_system[ManualPages_c]).assign_pages(
            [_system[PagesStatus_c], _system[PagesCommands_c], _system[PagesSession_c], _system[PagesUtility_c], _system[PagesAdmin_c]]);
    }

    function _init_devices() internal view {
        DeviceInfo[] devices;
        for ((, DeviceInfo dev): _multi)
            devices.push(dev);
        IDeviceManager(_system[DeviceManager_c]).init_devices{value: 0.1 ton, flag: 1}(devices);
    }

    function _flush_readers() internal view {
        for (uint8 i = 6; i < 10; i++)
            ICacheFS(_system[i]).flush_fs_cache();
        ICacheFS(_system[DeviceManager_c]).flush_fs_cache();
    }

    function init_x(uint8 n) external accept {
        if (n == 1)
            _init_config();
        if (n == 2)
            _init_devices();
        if (n == 3)
            _init_access_data();
        if (n == 4)
            _assign_pages();
        if (n == 26)
            _flush_readers();
        if (n == 28)
            ICacheFS(_system[DeviceManager_c]).flush_fs_cache();
        if (n == 30)
            _assign_readers();
    }

    function _init_config() internal {
        _assemble_device(Configure_c, address(this));
        _assemble_device(BuildFileSys_c, address(this));
    }

    function init_system() external view accept {
        _assign_readers();
        _init_devices();
        _init_access_data();
    }

    function deploy_system() external accept {
        address bdev = _assemble_device(BlockDevice_c, address(this));
        for (uint8 i = 1; i < 5; i++)
            _assemble_device(i, bdev);
        address pager = _assemble_device(ManualPages_c, bdev);
        for (uint8 i = 6; i < 10; i++)
            _assemble_device(i, bdev);
        for (uint8 i = 11; i < 16; i++)
            _assemble_device(i, pager);
        _assemble_device(Configure_c, address(this));
        _assemble_device(BuildFileSys_c, address(this));
        _live_update = true;
    }

    function _assemble_device(uint8 n, address source) internal returns (address addr) {
        (uint8 version, uint16 construction_cost, string description, uint16 block_size, uint16 n_blocks, TvmCell si, ) = _images[n].unpack();
        uint device_uid = (uint(block_size) << 80) + (uint(n_blocks) << 64) + (uint(version) << 40) + (uint(n) << 32) + _counter++;
        TvmCell new_si = tvm.insertPubkey(si, device_uid);
        addr = address.makeAddrStd(0, tvm.hash(new_si));
        DeviceInfo dev = DeviceInfo(n, version, description, block_size, n_blocks, addr);
        new Base{stateInit: new_si, value: uint64(construction_cost) * 1e9}(dev, source);
        _multi[n] = dev;
        _system[n] = addr;
        _roster.push(DeviceRecord(n, version, 0, now, addr));
    }

    function init_images(mapping (uint8 => DeviceImage) images) external override accept {
        _images = images;
        _system[AssemblyLine_c] = msg.sender;
        _system[BootManager_c] = address(this);
        (uint8 version, , string description, uint16 block_size, uint16 n_blocks, , ) = _images[AssemblyLine_c].unpack();
        _multi[AssemblyLine_c] = DeviceInfo(AssemblyLine_c, version, description, block_size, n_blocks, msg.sender);
        _multi[BootManager_c] = _dev;
    }

    function update_model(uint8 n, DeviceImage image) external override accept {
        _images[n] = image;
    }

    function upgrade_image(uint8 n, TvmCell c) external override accept {
        DeviceImage image = _images[n];
        image.model = c;
        image.version++;
        image.updated_at = now;
        _images[n] = image;
        if (_live_update) {
            Base(_system[n]).upgrade{value: 0.1 ton, flag: 1}(c);
            _multi[n].minor_id = image.version;
        }
    }

    function roster() external view returns (string out) {
        Column[] columns_format = [
            Column(true, 3, ALIGN_LEFT),
            Column(true, 3, ALIGN_LEFT),
            Column(true, 6, ALIGN_LEFT),
            Column(true, 66, ALIGN_LEFT),
            Column(true, 30, ALIGN_LEFT)];

        string[][] table = [["MAJ", "MIN", "ST", "Address", "Deployed at"]];
        for (DeviceRecord record: _roster) {
            (uint8 major_version, uint8 minor_version, uint8 status, uint32 assembly_time, address location) = record.unpack();
            table.push([
                format("{}", major_version),
                format("{}", minor_version),
                format("{}", status),
                format("{}", location),
                _ts(assembly_time)]);
        }
        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    function system() external view returns (string out) {
        Column[] columns_format = [
            Column(true, 3, ALIGN_LEFT),
            Column(true, 66, ALIGN_LEFT)];

        string[][] table = [["N", "Address"]];
        for ((uint8 n, address addr): _system)
            table.push([
                format("{}", n),
                format("{}", addr)]);
        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    function multi() external view returns (string out) {
        Column[] columns_format = [
            Column(true, 3, ALIGN_LEFT),
            Column(true, 3, ALIGN_LEFT),
            Column(true, 20, ALIGN_LEFT),
            Column(true, 5, ALIGN_LEFT),
            Column(true, 6, ALIGN_LEFT),
            Column(true, 66, ALIGN_LEFT)];

        string[][] table;
        for ((, DeviceInfo dev): _multi) {
                (uint8 major_id, uint8 minor_id, string name, uint16 block_size, uint16 n_blocks, address device_address) = dev.unpack();
                table.push([
                    format("{}", major_id),
                    format("{}", minor_id),
                    name,
                    format("{}", block_size),
                    format("{}", n_blocks),
                    format("{}", device_address)]);
        }
        out = _format_table_ext(columns_format, table, " ", "\n");
    }

    function etc_hosts() external view returns (string out) {
        Column[] columns_format = [
            Column(true, 66, ALIGN_LEFT),
            Column(true, 20, ALIGN_LEFT)];

        string[][] table;
        for ((uint8 n, address addr): _system)
            table.push([
                format("{}", addr),
                _images[n].description]);
        out = _format_table_ext(columns_format, table, "\t", "\n");
    }

    function update_code(TvmCell c) external {
        tvm.accept();
        TvmCell newcode = c.toSlice().loadRef();
        tvm.commit();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
    }

    function _init() internal override accept {}

}
