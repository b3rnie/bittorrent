
class BitfieldException < Exception; end

class Bitfield
  attr_reader :size

  def initialize(size)
    @size = size
    @data = Array.new(@size) { 0 }
  end

  def set(piece)
    assert_range(piece)
    @data[piece] = 1
  end

  def clear(piece)
    assert_range(piece)
    @data[piece] = 0
  end

  def is_set?(piece)
    assert_range(piece)
    @data[piece] == 1
  end

  def from_bytestring(s)
    new_data = s.unpack("B*")[0].chars.map(&:to_i)
    last_set = new_data.rindex { |piece| piece == 1 }
    if new_data.length != ((@size + 7) / 8) * 8 ||
        (last_set && last_set >= @size)
      fail BitfieldException, "wrong size bitfield"
    end
    @data = new_data[0,@size]
  end

  def to_bytestring
    puts @data.map(&:to_s).join.length
    res = [@data.map(&:to_s).join].pack("B*")
    res
  end

  def no_piece_set?
    @data.all? { |piece| piece == 0 }
  end

  def all_pieces_set?
    @data.all? { |piece| piece == 1 }
  end

  def -(other)
    bf = Bitfield.new(@size)
    (0..@size-1).each { |piece|
      if self.is_set?(piece) && !other.is_set?(piece)
        bf.set(piece)
      end
    }
    bf
  end

  def missing_pieces
    missing = []
    @data.each_with_index { |piece, index|
      missing.push(index) if piece == 0
    }
    missing
  end

  def existing_pieces
    existing = []
    @data.each_with_index { |piece, index|
      existing.push(index) if piece == 1
    }
    existing
  end

  private
  def assert_range(piece)
    if piece < 0 || piece >= @size
      fail BitfieldException, "piece out of range"
    end
  end
end
