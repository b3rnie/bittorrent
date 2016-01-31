module Conversions
  def Conversions.binary_id_to_int(id)
    raise "wrong size of #{id}" unless id.size == 20
    a = id.unpack("NNNNN")
    (a[0] << 32 * 4) |
    (a[1] << 32 * 3) |
    (a[2] << 32 * 2) |
    (a[3] << 32 * 1) |
    (a[4]          )
  end

  def Conversions.int_id_to_binary(id)
    [(id >> 32 * 4) & 0xFFFFFFFF,
     (id >> 32 * 3) & 0xFFFFFFFF,
     (id >> 32 * 2) & 0xFFFFFFFF,
     (id >> 32 * 1) & 0xFFFFFFFF,
     (id          ) & 0xFFFFFFFF].pack("NNNNN")
  end

  def Conversions.string_ip_to_int(ip)
    parts = ip.split('.').map { |i| i.to_i }
    raise "wrong number of parts #{parts}" unless parts.size == 4
    (parts[0] << 8 * 3) |
    (parts[1] << 8 * 2) |
    (parts[2] << 8 * 1) |
    (parts[3])
  end

  def Conversions.binary_id_to_hex(id)
    raise "wrong size of #{id}" unless id.size == 20
    id.unpack("H*")[0].rjust(40, "0")
  end

  def Conversions.hex_id_to_binary(id)
    raise "wrong size of #{id}" unless id.size == 40
    [id].pack("H*")
  end

  def Conversions.hex_id_to_int(id)
    raise "wrong size of #{id}" unless id.size == 40
    # id.to_i(16)
    id.hex
  end

  def Conversions.xor_binary(bin1, bin2)
    raise "wrong size of #{bin1} #{bin2}" unless bin1.size == 20 && bin2.size == 20
    bin1.unpack("C*")
      .zip(bin2.unpack("C*"))
      .map { |a,b| a ^ b }
      .pack("C*")
  end

  def Conversions.xor_hex(str1, str2)
    raise "wrong size of #{str1} #{str2}" unless str1.size == 40 && str2.size == 40
    (str1.hex ^ str2.hex).to_s(16).rjust(40, "0")
  end
end
