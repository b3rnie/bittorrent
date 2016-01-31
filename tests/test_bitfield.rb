
require 'client/bitfield'
require "test/unit"

class TestBitfield < Test::Unit::TestCase

  def test_simple
    b = Bitfield.new(10)
    assert(!b.is_set?(0))
    b.set(0)
    assert(b.is_set?(0))
    b.clear(0)
    assert(!b.is_set?(0))
    assert(!b.is_set?(9))
    b.set(9)
    assert(b.is_set?(9))
    b.clear(9)
    assert(!b.is_set?(9))
  end

  def test_out_of_range
    b = Bitfield.new(20)
    assert_raise(BitfieldException) {
      b.set(20)
    }
    assert_raise(BitfieldException) {
      b.clear(20)
    }
    assert_raise(BitfieldException) {
      b.set(-1)
    }
  end

  def test_from_bytestring
    b = Bitfield.new(1)
    b.from_bytestring([1 << 7].pack("C"))
    assert(b.is_set?(0))

    b = Bitfield.new(18)
    b.from_bytestring([0xFF, 0xFF, (1 << 7) + (1 << 6)].pack("CCC"))
    assert_raise(BitfieldException) {
      b.from_bytestring([0xFF, 0xFF, 0xFF, 0xFF].pack("C*"))
    }
    assert_raise(BitfieldException) {
      b.from_bytestring([0xFF, 0xFF].pack("C*"))
    }
  end

  def test_intersection
    b1 = Bitfield.new(10)
    b2 = Bitfield.new(10)
    b1.set(0)
    b1.set(1)
    b1.set(2)
    assert(b1.intersection(b2).no_piece_set?)
    b2.set(2)
    assert(b1.intersection(b2).is_set?(2))

    assert_raise(BitfieldException) {
      assert(b1.intersection(Bitfield.new(11)))
    }
  end

  def test_failure
    # assert_equal(3, SimpleNumber.new(2).add(2), "Adding doesn't work" )
  end

end


