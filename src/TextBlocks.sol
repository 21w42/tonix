pragma ton-solidity >= 0.49.0;

contract TextBlocks {
    uint8 public _major_id;
    uint8 public _minor_id;
    uint16 public _blk_size;
    uint16 public _n_blocks;
    uint32 public _counter;

    string[] public _blocks;

	constructor() public {
        tvm.accept();
    }

    function write(string[] blocks) external {
        tvm.accept();
        for (string s: blocks)
            _blocks.push(s);
    }

    function to_blocks(string text) external view returns (string[] blocks) {
        uint text_len = text.byteLength();
        uint block_size = _blk_size;
        uint n_chunks = text_len / block_size + 1;
        for (uint i = 0; i < n_chunks; i++)
            blocks.push(text.substr(i * block_size, i + 1 < n_chunks ? block_size : text_len - block_size * i));
    }

    function decode_uid() external {
        tvm.accept();
        uint device_uid = tvm.pubkey();
        _blk_size = uint16(device_uid >> 80);
        _n_blocks = uint16((device_uid >> 64) & 0xFFFF);
        _minor_id = uint8((device_uid >> 40) & 0xFF);
        _major_id = uint8((device_uid >> 32) & 0xFF);
        _counter = uint32(device_uid & 0xFFFFFFFF);
    }

}
