require "yaml"
require "./singleton"
require "./supcurses"

module Redwood

# `Colormap` is a singleton class responsible for the mapping of logical
# color names (`text_color`, `status_color`, `label_color`, etc.) into
# on-screen (Ncurses) colorpairs.  It defines many default colors,
# but also reads user-defined colors from `~/.csup/colors.yaml`.
class Colormap
  singleton_class

  # `ColorEntry` contains the Ncurses color values for a single color:
  # the foreground color (`fg`), background color (`bg`), and one or more attributes (`attrs`).
  # The `color` property contains an Ncurses colorpair value; it is initially
  # nil, and is filled in as needed, because Ncurses supports a limited
  # number of colorpairs.
  class ColorEntry
    property fg : Int32
    property bg : Int32
    property attrs : Array(Int32)
    property color : Int32 | Nil

    def initialize(@fg, @bg, @attrs = [] of Int32, @color = nil)
    end

    def tuple
      {fg, bg, attrs, color}
    end
  end

  @@default_colors = {
    "text" => { "fg" => "white", "bg" => "black" },
    "status" => { "fg" => "white", "bg" => "blue", "attrs" => ["bold"] },
    "index_old" => { "fg" => "white", "bg" => "default" },
    "index_new" => { "fg" => "white", "bg" => "default", "attrs" => ["bold"] },
    "index_starred" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "index_draft" => { "fg" => "red", "bg" => "default", "attrs" => ["bold"] },
    "labellist_old" => { "fg" => "white", "bg" => "default" },
    "labellist_new" => { "fg" => "white", "bg" => "default", "attrs" => ["bold"] },
    "twiddle" => { "fg" => "blue", "bg" => "default" },
    "label" => { "fg" => "yellow", "bg" => "default" },
    "message_patina" => { "fg" => "black", "bg" => "green" },
    "alternate_patina" => { "fg" => "black", "bg" => "blue" },
    "missing_message" => { "fg" => "black", "bg" => "red" },
    "attachment" => { "fg" => "cyan", "bg" => "default" },
    "cryptosig_valid" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "cryptosig_valid_untrusted" => { "fg" => "yellow", "bg" => "blue", "attrs" => ["bold"] },
    "cryptosig_unknown" => { "fg" => "cyan", "bg" => "default" },
    "cryptosig_invalid" => { "fg" => "yellow", "bg" => "red", "attrs" => ["bold"] },
    "generic_notice_patina" => { "fg" => "cyan", "bg" => "default" },
    "quote_patina" => { "fg" => "yellow", "bg" => "default" },
    "sig_patina" => { "fg" => "yellow", "bg" => "default" },
    "quote" => { "fg" => "yellow", "bg" => "default" },
    "sig" => { "fg" => "yellow", "bg" => "default" },
    "to_me" => { "fg" => "green", "bg" => "default" },
    "with_attachment" => { "fg" => "green", "bg" => "default" },
    "starred" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "starred_patina" => { "fg" => "yellow", "bg" => "green", "attrs" => ["bold"] },
    "alternate_starred_patina" => { "fg" => "yellow", "bg" => "blue", "attrs" => ["bold"] },
    "snippet" => { "fg" => "cyan", "bg" => "default" },
    "option" => { "fg" => "white", "bg" => "default" },
    "tagged" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "draft_notification" => { "fg" => "red", "bg" => "default", "attrs" => ["bold"] },
    "completion_character" => { "fg" => "white", "bg" => "default", "attrs" => ["bold"] },
    "horizontal_selector_selected" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "horizontal_selector_unselected" => { "fg" => "cyan", "bg" => "default" },
    "search_highlight" => { "fg" => "black", "bg" => "yellow", "attrs" => ["bold"] },
    "system_buf" => { "fg" => "blue", "bg" => "default" },
    "regular_buf" => { "fg" => "white", "bg" => "default" },
    "modified_buffer" => { "fg" => "yellow", "bg" => "default", "attrs" => ["bold"] },
    "date" => { "fg" => "white", "bg" => "default"},
    "size_widget" => { "fg" => "white", "bg" => "default"},
  }

  # Instance variables

  @highlights = {} of String => String
  @entries = {} of String => ColorEntry
  @filename : String

  # Cache of Ncurses colorpairs, indexed by {fg, bg} tuple.
  @color_pairs = {[Ncurses::COLOR_WHITE, Ncurses::COLOR_BLACK] => 0}

  # Table of names of colors that use the same colorpair.
  @users = {} of Int32 => Array(String)     # colorpair => [names of colors]
  @next_id = 0

  def initialize(@filename)
    singleton_pre_init
    reset
    singleton_post_init
  end

  # Clears the colormap (`@entries`) to their initial, nearly empty state.
  def reset
    @entries = Hash(String, ColorEntry).new
    @highlights = { "none" => highlight_sym("none")}
    @entries[highlight_sym("none")] = highlight_for(Ncurses::COLOR_WHITE,
                                                   Ncurses::COLOR_BLACK,
                                                   [] of Int32)
  end
  singleton_method reset

  # Adds an entry to the colormap (`@entries`):
  #
  # * *sym*: the name of the color
  # * *fg*: Ncurses foreground color
  # * *bg*: Ncurses background color
  # * *attr*: array of Ncurses cell attributes
  # * *highlight*: name of the corresponding highlight color
  def add(sym : String, fg : Int32, bg : Int32, attr : Array(Int32), highlight : String | Nil)
    # Ruby raise accepts a second string parameter, not supported in Crystal.
    # How to handle this difference correctly?
    raise ArgumentError.new("color for #{sym} already defined") if @entries.has_key?(sym)
    raise ArgumentError.new("fg color '#{fg}' unknown") unless (-1...Ncurses.num_colors).includes? fg
    raise ArgumentError.new("bg color '#{bg}' unknown") unless (-1...Ncurses.num_colors).includes? bg
    attrs = [attr].flatten.compact

    @entries[sym] = ColorEntry.new(fg, bg, attrs, nil)
    #debug "added entry for #{sym}, fg #{fg}, bg #{bg}, attrs #{attrs}"
    if highlight.nil?
      highlight = highlight_sym(sym)
      @entries[highlight] = highlight_for(fg, bg, attrs)
    end

    @highlights[sym] = highlight
  end

  # Returns the name *sym* with the "_highlight" suffix, used when
  # defining a color entry for a highlighted version of a normal color.
  def highlight_sym(sym : Symbol | String) : String
    return sym.to_s + "_highlight"
  end

  # Returns a new color entry for a highlighted version of the specified
  # Ncurses colors and attributes:
  #
  # * *fg*: Ncurses foreground color
  # * *bg*: Ncurses background color
  # * *attrs*: array of Ncurses cell attributes
  def highlight_for(fg, bg, attrs)
    hfg =
      case fg
      when Ncurses::COLOR_BLUE
        Ncurses::COLOR_WHITE
      when Ncurses::COLOR_YELLOW, Ncurses::COLOR_GREEN
        fg
      else
        Ncurses::COLOR_BLACK
      end

    hbg =
      case bg
      when Ncurses::COLOR_CYAN
        Ncurses::COLOR_YELLOW
      when Ncurses::COLOR_YELLOW
        Ncurses::COLOR_BLUE
      else
        Ncurses::COLOR_CYAN
      end

    attrs =
      if fg == Ncurses::COLOR_WHITE && attrs.includes?(Ncurses::A_BOLD)
        [Ncurses::A_BOLD]
      else
        case hfg
        when Ncurses::COLOR_BLACK
          [] of Int32
        else
          [Ncurses::A_BOLD]
        end
      end
    return ColorEntry.new(hfg, hbg, attrs)
  end

  # Returns the Ncurses colorpair value for the color whose name is *name*.
  # If *highlight* is true, returns the highlighted version of the color.
  #
  # Because Ncurses supports a limited number of active colorpairs,
  # old colorpair slots will get reused if more colors than that limit
  # are used simultaneously.  This should never happen, but `color_for`
  # will display a warning if it does.
  def color_for(name : Symbol | String, highlight=false) : Int32
    sym = name.to_s
    sym = @highlights[sym] if highlight
    return Ncurses::COLOR_BLACK if sym == "none"
    raise ArgumentError.new("undefined color #{sym}") unless @entries.has_key?(sym)

    # If this color is cached, return it.
    fg, bg, attrs, color = @entries[sym].tuple
    #debug "entries[#{sym}] = #{fg}, #{bg}, #{attrs}, #{color}"
    return color if color

    if @color_pairs.has_key?([fg, bg])
      cp = @color_pairs[[fg, bg]]
      ## nothing
    else ## need to get a new colorpair.
      @next_id = (@next_id + 1) % Ncurses.max_pairs
      @next_id += 1 if @next_id == 0 # 0 is always white on black
      id = @next_id
      #debug "colormap: for color #{sym}, using id #{id} -> #{fg}, #{bg}"
      Ncurses.init_pair(id.to_i16, fg.to_i16, bg.to_i16) ||
        raise ArgumentError.new("couldn't initialize curses colorpair #{fg}, #{bg} (key #{id})")

      cp = @color_pairs[[fg, bg]] = LibNCurses.COLOR_PAIR(id)
      #debug "colormap: color_pair for id #{id} = #{cp}"
      ## delete the old mapping, if it exists
      if @users.has_key?(cp)
        u = @users[cp]
	if u
	  u.each do |usym|
            warn "dropping color #{usym} (#{id})"
            @entries[usym].color = nil
	  end
        end
        @users[cp] = [] of String
      end
    end

    ## by now we have a colorpair
    color = attrs.reduce(cp) { |color, attr| color | attr }
    @entries[sym].color = color # fill the cache
    # record entry as a user of that colorpair
    if @users.has_key?(cp)
      @users[cp] << sym
    else
      @users[cp] = [sym]
    end
    color
  end
  singleton_method color_for, sym

  # If there is a color with the name *name*, returns that name;
  # otherwise returns nil.
  def sym_is_defined(name : Symbol | String) : String?
    sym = name.to_s
    #debug "checking if @entries has key #{sym}"
    if @entries.has_key?(sym)
      return sym
    else
      return nil
    end
  end
  singleton_method sym_is_defined, sym

  # Reads the user-defined colors from `~/.csup/colors.yaml` into
  # a colormap hash and returns it.
  def load_user_colors
    yaml = File.open(@filename) { |f| YAML.parse(f) }
    colors = Hash(String, Hash(String, String | Array(String))).new
    h = yaml.as_h
    h.each do |k, v|
      key = k.as_s.lstrip(':')
      h1 = v.as_h
      #debug "Key: #{key}"
      colors[key] = Hash(String, String | Array(String)).new
      h1.each do |k1, v1|
	key1 = k1.as_s.lstrip(':')
	if key1 == "attrs"
	  attrs = Array(String).new
	  val1 = v1.as_a
	  val1.each_with_index do |v2, i|
	    val2 = v2.as_s
	    #debug "  attr[#{i}] = #{val2}"
	    attrs << val2
	  end
	  colors[key]["attrs"] = attrs
	else
	  val1 = v1.as_s
	  colors[key][key1] = val1
	  #debug "  #{key1}=#{val1}"
	end
      end
    end

    #debug "colors after load_user_colors:\n#{colors.inspect}"
    return colors
  end

  # Loads the user colors from `~/.csup/colors.yaml` into the colormap,
  # then adds default colors to the colormap to fill in the blanks.
  def populate_colormap
    user_colors = load_user_colors

    # Set attachment symbol to sane default for existing colorschemes
    if user_colors && user_colors.has_key? "to_me"
      user_colors["with_attachment"] = user_colors["to_me"] unless user_colors.has_key? "with_attachment"
    end

    @@default_colors.merge(user_colors).each do |k, v|
      fg = begin
        Ncurses.const_get "COLOR_#{v["fg"].to_s.upcase}"
      rescue NameError
        warn "there is no fg color named \"#{v["fg"]}\""
        Ncurses::COLOR_GREEN
      end

      bg = begin
        Ncurses.const_get "COLOR_#{v["bg"].to_s.upcase}"
      rescue NameError
        warn "there is no bg color named \"#{v["bg"]}\""
        Ncurses::COLOR_RED
      end

      attrs = [] of Int32
      if v.has_key?("attrs")
	at = v["attrs"].as(Array(String))
	at.each do |a|
	  begin
	    attrs << Ncurses.const_get "A_#{a.upcase}"
	  rescue NameError
	    warn "there is no attribute named \"#{a}\", using fallback."
	  end
	end
      end
      if v.has_key?("highlight")
	s = v["highlight"].as(String)
	highlight_symbol = s + "_color"
      else
	highlight_symbol = nil
      end
      symbol = k + "_color"
      add symbol, fg, bg, attrs, highlight_symbol
    end
    #debug "@entries after populate_color_map:\n#{@entries.inspect}"
  end
  singleton_method populate_colormap

end	# class Colormap

end	# module Redwood
