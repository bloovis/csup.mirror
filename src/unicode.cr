#require "ncurses"

lib LibC
  alias WChar = UInt32

  fun wcswidth(s : WChar*, n : SizeT) : Int
  fun wcwidth(c : WChar) : Int
end

# The `Unicode` module provides the barest minimum compatibility
# with the Ruby version that is required by csup.
module Unicode
  extend self

  # Returns the display width of a UTF-8 character string.
  def width(s : String) : Int32
    width = 0
    chreader = Char::Reader.new(s)
    chreader.each do |ch|
      wc : LibC::WChar = ch.ord.to_u
      wclen = LibC.wcwidth(wc)
      if wclen < 0
	wclen = 1
      end
      width += wclen
    end
    width
  end

end
