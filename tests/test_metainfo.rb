
require 'client/metainfo'
require "test/unit"

class TestMetainfo < Test::Unit::TestCase
  def test_simple
    m = Metainfo.new(:file => "tests/metainfo_0.torrent")
  end
end


