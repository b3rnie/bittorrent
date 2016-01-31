
require 'client/metainfo'
require 'client/torrent_io'
require "test/unit"

class TestTorrentIO < Test::Unit::TestCase
  def test_simple
    metainfo  = Metainfo.new(:file => "tests/metainfo_1.torrent")
    torrentio = TorrentIO.new(:path => "foo",
                              :metainfo => metainfo)
  end
end


