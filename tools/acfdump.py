import struct, sys
d = open(sys.argv[1], 'rb').read()
hdr = struct.unpack_from('<I24s16s4sIIIII', d, 0)
idv, proj, cust, ver, author, ddt_size, ddt_num, hdr_off, hdr_ver = hdr
print(f"id=0x{idv:x} project={proj.rstrip(b'\0')} custom={cust.rstrip(b'\0')} ver={ver.hex()} ddt_size={ddt_size} ddt_num={ddt_num} hdr_off={hdr_off} hdr_ver=0x{hdr_ver:x}")
for i in range(ddt_num):
    o = hdr_off + i * 64
    t, name, idx, bus, addr, prof, dtype, dsize, doff, crc = struct.unpack_from('<I16sHHHHIIII', d, o)
    extra = ''
    if False:
        pstr, chip = struct.unpack_from('<32sI', d, o + 52)
        extra = f" prof_str={pstr.rstrip(b'\0').decode(errors='replace')!r} chip=0x{chip:x}"
    print(f"[{i:2}] type=0x{t:x} dev={name.split(b'\0')[0].decode(errors='replace')} index={idx} bus={bus} addr=0x{addr:x} prof={prof} data_type={dtype} size={dsize} off={doff}{extra}")
