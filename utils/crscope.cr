# crscope - cscope-like cross-reference tool for Crystal
#
# I've used cscope for decades to examine C source trees.  I also added
# commands to my MicroEMACS editor to use cscope without leaving
# the editor.  This program implements a subset of the cscope features,
# but for Crystal source trees.  Because MicroEMACS only needs the
# line-oriented interface of cscope, that's the only interface I
# implemented for crscope.
#
# Also, due to the difficulty of parsing Crystal, crscope uses very crude
# heuristics for locating the definitions of methods, class, modules, libraries,
# and constants.  For example, it assumes that the indention of a "class" or
# "def" statement is the same as the indention for the matching "end" statement.
# Furthermore, crscope does not attempt to find all uses of a particular symbol.
#
# The three search types that crscope implements are:
#
# 0 - Find all (possibly inexact) matches for a method.  Thus,
#     searching for "print" will find "Class1.print", "Class2.print", etc.
# 1 - Find exact match for a method.  This requires that you enter a
#     fully-qualified name, where "." separates all class names.
# 6 - Perform an egrep search.
# 7 - Perform a file search.
#
# Crscope parses files you specify on the command line, or can
# parse the files that you list in crscope.files.  It writes the
# results of its parsing to crscope.out, which is plain-text file.

require "option_parser"
require "../src/pipe"
require "../src/supcurses"

class Config
  def self.bool(sym)
    false
  end
end

class String
  # Calculate display length, taking into account the size of a tab.
  def display_size(tabsize = 8)
    len = 0
    self.each_char do |c|
      if c == '\t'
	len = len + tabsize - (len % tabsize)
      else
	len += 1
      end
    end
    len
  end

  # Return the common part of two strings.
  def common(s : String)
    len = [self.size, s.size].min
    max = len
    (0...len).each do |i|
      if self[i] != s[i]
        max = i
	break
      end
    end
    return self[0,max]
  end

  def pad_left(width : Int32)
    pad = width - self.size
    " " * pad + self
  end

  def pad_right(width : Int32)
    pad = width - self.size
    self + " " * pad
  end
end

# Class used to record a single result of a search.
class Result
  property filename : String
  property name : String
  property line : Int32
  property context : String

  def initialize(@filename, @name, @line, @context)
  end
end

# Class used to record all name definitions for a single file.
class FileDefs

  # Class used to record a name definition.
  class Def
    property name : String
    property lineno : Int32
    property indent : Int32
    property context : String

    def initialize(@name, @lineno, @indent, @context)
      #puts "Def.initialize #{@name}:#{@lineno}:#{@indent}:#{@context}"
    end
  end

  property filename = ""

  # Ephemeral stack of modules and classes, used only during parsing.
  property class_stack = [] of Def

  # Permanent record of defintions, using fully qualified names.
  property records = [] of Def

  property debug = false
  property tabsize = 8

  def initialize(@filename : String, @debug = false, @tabsize = 8)
  end

  def parse_file
    dprint "FileDefs.parse_file: filename #{@filename}, tabsize #{@tabsize}"
    File.open(@filename) do |f|
      lineno = 1
      f.each_line(chomp: true) do |line|
	#puts "line #{lineno}: #{line.strip}"
	# Handle the following unusual cases:
	# - one-line class (e.g. Class Blotz ; ... ; end)
	# - double-colon qualified class (e.g. class Blotz::Blivot):
	#   replace the :: with .
	if line =~ /^(\s*)(class|module|lib)\s+([\w:]+)/
	  space = $1
	  name = $3.gsub("::", ".")
	  one_line = false
	  if line =~ /;\s*end\s*$/
	    one_line = true
	  end
	  add_class(name, space.display_size(tabsize), lineno, space.size, line.strip,
		    one_line)
	elsif line =~ /^(\s*)abstract\s*class\s+([\w:]+)/
	  space = $1
	  name = $2.gsub("::", ".")
	  one_line = false
	  if line =~ /;\s*end\s*$/
	    one_line = true
	  end
	  add_class(name, space.display_size(tabsize), lineno, space.size, line.strip,
		    one_line)
	elsif line =~ /^(\s*)def\s+(self\.)?(\w+)/
	  add_method($3, $1.display_size(tabsize), lineno, $1.size, line.strip)
	elsif line =~ /^(\s*)end(\s|$)/
	  pop_defs($1.display_size(tabsize))
	elsif line =~ /^(\s*)(fun|alias)\s+(\w+)/
	  add_name($3, lineno, $1.display_size(tabsize), line.strip)
	elsif line =~ /^(\s*)([A-Z_]+)\s*=/
	  add_name($2, lineno, $1.display_size(tabsize), line.strip)
	end
	lineno += 1
      end
    end
  end

  def dprint(s : String)
    puts s if @debug
  end

  def add_class(name : String, indent : Int32, lineno : Int32, column : Int32,
		context : String, one_line = false)
    dprint "add_class: name #{name}, indent #{indent}, lineno #{lineno}, one_line #{one_line}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    unless one_line
      class_stack.push (Def.new(name, lineno, indent, context))
    end
    records.push (Def.new(full_name, lineno, column, context))
  end

  def add_method(name : String, indent : Int32, lineno : Int32, column : Int32, context : String)
    dprint "add_method: name #{name}, indent #{indent}, lineno #{lineno}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    records.push (Def.new(full_name, lineno, column, context))
  end

  def add_name(name : String, lineno : Int32, column : Int32, context : String)
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    records.push (Def.new(full_name, lineno, column, context))
  end

  def pop_defs(indent : Int32)
    dprint "pop_defs: indent #{indent}"
    if class_stack.size > 0 && indent <= class_stack[-1].indent
      d = class_stack.pop
      dprint "Popped class #{d.name}"
    end
  end

  def print(f : IO)
    dprint "FileDefs.print"
    records.each do |r|
      f.puts "#{r.name}|#{@filename}:#{r.lineno}:#{r.indent+1}|#{r.context}"
    end
  end
end

# Class defining an entry field in the search form.
class Entry
  property prompt : String	# prompt string
  property row : Int32		# line number on screen
  property type : Int32		# 0, 1, 6, or 7
  property buf : String		# entry buffer
  property leftcol : Int32 	# starting column for entry
  property fillcols : Int32	# number of columns to right of prompt

  # Values for type.
  TYPE_INEXACT = 0
  TYPE_EXACT   = 1
  TYPE_GREP    = 6
  TYPE_FILE    = 7

  def initialize(@prompt, @row, @type)
    @buf = ""
    @leftcol = prompt.size + 1
    @fillcols = Ncurses.cols - @leftcol
    Ncurses.mvaddstr @row, 0, @prompt
  end

  alias CompletionProc = Proc(String)

  # Prompt the user to enter a string for this entry, and return the last character
  # typed (Enter, Up, Down, or C-d). The passed-in completion proc takes a prefix
  # and returns the longest possible suffix for that prefix.
  def get_entry(&block : CompletionProc) : String
    Ncurses.mvaddstr(@row, 0, @prompt)
    Ncurses.move(@row, @leftcol)
    Ncurses.clrtoeol
    Ncurses.curs_set 1
    Ncurses.refresh

    pos = @buf.size
    done = false
    aborted = false
    lastc = ""
    while true
      # Redraw the @buf buffer.
      if @buf.size >= fillcols
	# Answer is too big to fit on screen.  Just show the right portion that
	# does fit.
	Ncurses.mvaddstr(@row, @leftcol, @buf[@buf.size-fillcols..@buf.size-1])
        Ncurses.move(@row, Ncurses.cols - 1)
      else
        Ncurses.mvaddstr(@row, @leftcol, @buf + (" " * (fillcols - @buf.size)))
        Ncurses.move(@row, @leftcol + pos)
      end
      Ncurses.refresh

      c = Ncurses.getkey
      next if c == ""
      case c
      when "C-a"
        pos = 0
      when "C-e"
        pos = @buf.size
      when "Left", "C-b"
        if pos > 0
	  pos -= 1
	end
      when "Right", "C-f"
        if pos < @buf.size
	  pos += 1
	end
      when "C-h", "Delete"
        if !(c == "C-h" && pos == 0)
	  if c == "C-h"
	    pos -= 1
	  end
	  left = (pos == 0) ? "" : @buf[0..pos-1]
	  right = (pos >= @buf.size - 1) ? "" : @buf[pos+1..]
	  @buf = left + right
	end
      when "C-k"
        if pos == 0
	  @buf = ""
	else
	  @buf = @buf[0..pos-1]
	end
      when "C-u"
        @buf = ""
	pos = 0
      when "?"
        if @type != TYPE_GREP
	  suffix = yield
	  @buf = @buf.insert(pos, suffix)
	  pos += suffix.size
	end
      when "C-m", "C-d", "Up", "Down", "C-g", "C-n", "C-p", "C-i"
        return c
      else
	if c.size == 1
	  @buf = @buf.insert(pos, c)
	  pos += 1
	end
      end
      lastc = c
    end
  end
end

class Index
  property fdefs = Hash(String, FileDefs).new	# indexed by filelname
  property debug = false
  property tabsize = 8
  property nrows = 0		# total number of lines in terminal window
  property result_rows = 0 	# space for results at top of screen
  property results = [] of Result

  def initialize(@debug, @tabsize)
  end

  def add_file(f : FileDefs)
    fdefs[f.filename] = f
    #puts "Index.add_file #{f.filename}"
  end

  def parse_files(filenames : Array(String))
    filenames.each do |filename|
      puts "parsing #{filename}" if debug
      fdef = FileDefs.new(filename, debug, tabsize)
      fdef.parse_file
      fdef.print(STDOUT) if debug
      add_file(fdef)
    end
  end

  def read_database(infile : String)
    File.open(infile, "r") do |f|
      f.each_line(chomp: true) do |line|
        splits = line.split("|")
	name = splits[0]
	file = splits[1]
	context = splits[2]

	file_splits = file.split(":")
	filename = file_splits[0]
	lineno = file_splits[1].to_i
	indent = file_splits[2].to_i - 1
	unless fdef = fdefs[filename]?
	  fdef = FileDefs.new(filename, debug, tabsize)
	  fdefs[filename] = fdef
	end
	fdef.records.push(FileDefs::Def.new(name, lineno, indent, context))
      end
    end
  end

  def write_database(outfile : String)
    File.open(outfile, "w") do |f|
      fdefs.each do |filename, fdef|
	#puts "Index.print #{filename}"
	fdef.print(f)
      end
    end
  end

  def print
    fdefs.each do |filename, fdef|
      fdef.print(STDOUT)
    end
  end

  def search(name : String, exact_match = false, partial_match = false) : Array(Result)
    primary_results = [] of Result
    secondary_results = [] of Result
    fdefs.each do |filename, fdef|
      fdef.records.each do |r|
	if partial_match
	  # partial_match means the name in the symbol table only has to start
	  # with the name being searched, i.e., not match it entirely.
	  if exact_match
	    # We must include any classname qualifications in the match.
	    if r.name.starts_with?(name)
	      primary_results.push(Result.new(filename, r.name, r.lineno,r.context))
	    end
	  else
	    # We can ignore any or all classname qualifications in the match.
	    regexp = Regex.new("^.*[.]?(#{name}[^\.]*)$")
	    match = regexp.match(r.name)
	    if match && match[1]?
	      secondary_results.push(Result.new(filename, match[1], r.lineno,r.context))
	    end
	  end
        elsif exact_match
	  if r.name == name
	    # exact_match means the names must be identical.
	    primary_results.push(Result.new(filename, r.name, r.lineno,r.context))
	  end
	else
	  # exact_match is false, which means the name being searched doesn't need to match
	  # any of the class name qualifications of the name in the symbol table.
	  regexp = Regex.new("(^|\\.)#{name}$")
	  match = regexp.match(r.name)
	  if match
	    secondary_results.push(Result.new(filename, r.name, r.lineno,r.context))
	  end
	end
      end
    end
    return primary_results + secondary_results
  end

  def grepsearch(name : String) : Array(Result)
    results = [] of Result
    # Get the list of filenames, either from crscope.files,
    # or from the filenames listed in crscope.out.
    if File.exists?("crscope.files")
      filenames = File.read_lines("crscope.files", chomp: true)
    else
      filenames = fdefs.each.map {|filename, fdef| filename}
    end
    filenames.each do |filename|
      pipe = Redwood::Pipe.new("grep", ["-E", "-n", name, filename])
      pipe.start do |p|
        p.receive do |f|
	  while s = f.gets(chomp: true)
	    if s =~ /^(\d+):(.*)/
	      lineno = $1.to_i
	      context = $2
	      results.push(Result.new(filename, "<unknown>", lineno, context))
	    end
	  end
	end
      end
    end
    return results
  end

  def filesearch(name : String) : Array(Result)
    results = [] of Result
    fdefs.each do |filename, fdef|
      if filename =~/#{name}/
	results.push(Result.new(filename, "<unknown>", 1, "<unknown>"))
      end
    end
    return results
  end

  def line_interface
    while true
      STDOUT.print ">> "
      STDOUT.flush
      line = STDIN.gets
      return if line.nil?
      search_type = line[0].to_i
      search_term = line[1..]
      results = [] of Result
      case search_type
      when Entry::TYPE_INEXACT
        results = search(search_term, exact_match: false)
      when Entry::TYPE_EXACT
        results = search(search_term, exact_match: true)
      when Entry::TYPE_GREP
	results = grepsearch(search_term)
      when Entry::TYPE_FILE
	results = filesearch(search_term)
      else
	puts "Unknown search type #{search_type}"
      end
      if results.size > 0
	STDOUT.puts "cscope: #{results.size} lines"
	results.each do |r|
	  STDOUT.puts "#{r.filename} #{r.name} #{r.line} #{r.context}"
	end
      else
	STDOUT.puts "no results"
      end
    end
  end
	
  # Convert an integer from 0 to 62 to a digit or a letter, for use
  # in the left column of the search results display.
  def char_for(n : Int32) : String
    if n < 10
      return ('0' + n).to_s
    elsif n < 36
      return ('a' + (n - 10)).to_s
    else
      return ('A' + (n - 36)).to_s
    end
  end

  # Display results, and return the number actually shown.
  # The offset parameter says how many results to skip,
  # which we use when there are more results than will fit on the screen.
  def show_results (offset : Int32) : Int32
    shown = [@results.size - offset, @result_rows - 2, 62].min
    Ncurses.move 0, 0
    Ncurses.clrtoeol

    # Calculate maximum lengths of files, names, and line numbers.
    flen = "File".size
    nlen = "Name".size
    llen = "Line".size
    shown.times do |i|
      r = @results[i + offset]
      flen = [flen, Path[r.filename].basename.size].max
      nlen = [nlen, r.name.size].max
      llen = [llen, r.line.to_s.size].max
    end

    # Display the header line
    Ncurses.mvaddstr 0, 0,
      "  " +
      "File".pad_right(flen) + " " +
      "Name".pad_right(nlen) + " " +
      "Line".pad_right(llen)

    # Display the results with fields padded nicely.
    (0..@result_rows-1).each do |i|
      Ncurses.move i + 1, 0
      Ncurses.clrtoeol
      if i < shown
	r = @results[i + offset]
	Ncurses.mvaddstr i + 1, 0,
	  "#{char_for(i)} " +
	  "#{Path[r.filename].basename.pad_right(flen)} " +
	  "#{r.name.pad_right(nlen)} " +
	  "#{r.line.to_s.pad_left(llen)} " +
	  "#{r.context}"
      end
    end
    return shown
  end

  # Perform a search appropriate for this entry's type (exact, inexact, regexp, file).
  def entry_search(entry : Entry, partial_match = false) : Array(Result)
    results = [] of Result
    s = entry.buf
    case entry.type
    when Entry::TYPE_INEXACT
      results = search(s, exact_match: false, partial_match: partial_match)
    when Entry::TYPE_EXACT
      results = search(s, exact_match: true, partial_match: partial_match)
    when Entry::TYPE_GREP
      results = grepsearch(s)
    when Entry::TYPE_FILE
      results = filesearch(s)
    end
    return results
  end

  def run_editor(filename : String, line : Int32)
    editor = ENV["EDITOR"]? || ENV["VISUAL"]? || "nano"
    if editor
      format = ENV["CRSCOPE_EDITOR"]? || "%e +%l %f"
      command = format.gsub("%e", editor).
		       gsub("%l", line).
		       gsub("%f", filename)
      Ncurses.endwin
      success = system command
      Ncurses.stdscr.keypad true
      Ncurses.refresh
      Ncurses.curs_set 1
      #Ncurses.mvaddstr 0, 0, "Editor returned #{success}"
    else
      Ncurses.mvaddstr 0, 0, "Environment variable EDITOR not defined!"
      Ncurses.clrtoeol
    end
  end

  # Move the cursor to the results at the top of the screen
  # and allow the user to select a result, which will
  # invoke $EDITOR on the selected file and line.
  # Return the last key entered by the user (C-d or C-i).
  def move_to_results : String
    done = false
    offset = 0
    c = ""
    i = 0
    shown = 0
    reload = true
    rsize = @results.size
    until done
      if reload
	shown = show_results(offset)
	reload = false
	more = @results.size - (offset + shown)
	if @results.size > @result_rows - 2
	  Ncurses.mvaddstr @result_rows, 0,
	    "* Lines #{offset + 1}-#{offset + shown} of #{rsize}, " +
	    "#{more} more - press Space to go forward, Backspace to go back *"
	end
      end
      Ncurses.move i + 1, 0
      c = Ncurses.getkey
      next if c == ""
      case c
      when " "
        offset += shown
	if offset < rsize
	  reload = true
	end
      when "C-h"
        if offset > 0
	  offset = [offset - @result_rows, 0].max
	  reload = true
	end
      when "C-m"
	run_editor(@results[i + offset].filename, @results[i + offset].line)
      when "Down", "C-n"
	if i == shown - 1
	  i = 0
	else
	  i += 1
	end
      when "Up", "C-p"
	if i == 0
	  i = shown - 1
	else
	  i -= 1
	end
      when "C-d", "C-i"
	done = true
      else
	if c.size == 1
	  ch = c[0]
	  n = -1
	  if ch >= '0' && ch <= '9'
	    n = ch - '0'
	  elsif ch >= 'a' && ch <= 'z'
	    n = ch - 'a' + 10
	  elsif ch >= 'A' && ch <= 'Z'
	    n = ch - 'A' + 36
	  end
	  if n != -1 && n < shown
	    run_editor(@results[n + offset].filename, @results[n + offset].line)
	  end
	end
      end
    end
    return c
  end

  def curses_interface
    Redwood.start_cursing
    Ncurses.curs_set 1

    @nrows = Ncurses.rows
    @results = [] of Result

    # Add the four entry fields.
    entries = [] of Entry
    row = @nrows - 1
    entries.push Entry.new("Inexact name search:", row-3, Entry::TYPE_INEXACT)
    entries.push Entry.new("Exact name search:",   row-2, Entry::TYPE_EXACT)
    entries.push Entry.new("Regexp search:",       row-1, Entry::TYPE_GREP)
    entries.push Entry.new("File search:",         row,   Entry::TYPE_FILE)
    @result_rows = @nrows - entries.size - 2	# 2 leaves space for a blank line plus a prompt line

    entry_number = 0
    done = false
    until done
      entry = entries[entry_number]
      c = entry.get_entry do
        # User hit ?, so try to do a completion.
	# First, get all partial matches.
	@results = entry_search(entry, partial_match: true)
	show_results(0)
	if @results.size == 0
	  Ncurses.mvaddstr 0, 0, "Could not find #{entry.buf}"
	end

	# Find the longest possible match for the string entered so far.
	s = entry.buf
	prefix = s
	suffix = ""
	longest = s
	if @results.size > 0 && entry.type != Entry::TYPE_FILE
	  longest = ""
	  @results.each do |r|
	    name = r.name
	    if name.starts_with?(prefix)
	      if longest == ""
		longest = name
	      else
		longest = longest.common(name)
	      end
	    end
	  end
	  #if prefix.size == 0
	  #  suffix = ""
	  #else
	  #  suffix = longest[prefix.size..]
	  #end
	end
	suffix
      end # End of completion code.

      # How we handle the entry depends on what the the user hit
      # to end it.
      # Tab - display partial matches
      # Enter - display inexact or exact matches
      case c
      when "C-d"
	done = true
      when "Down", "C-n"
        if entry_number == entries.size - 1
	  entry_number = 0
	else
	  entry_number += 1
	end
      when "Up", "C-p"
        if entry_number == 0
	  entry_number = entries.size - 1
	else
	  entry_number -= 1
	end
      when "C-m"
        # Show the results, and move the cursor to the results
	# so that the user can select one.  The user may
	# also choose to exit selection mode with Tab or C-d.
	@results = entry_search(entry, partial_match: false)
	show_results(0)
	if @results.size > 0
	  c = move_to_results
	  if c == "C-d"
	    done = true
	  end
	else
	  Ncurses.mvaddstr 0, 0, "Could not find #{entry.buf}"
	end
      when "C-i"
        if @results.size > 0
	  c = move_to_results
	  if c == "C-d"
	    done = true
	  end
	end
      end # case

    end # until done
    Redwood.stop_cursing
  end # curses_interface
	
end

# Usage: crscope [-l][-d][-k] file...
#
# -v	Verbose (debug) mode
# -l	Line-oriented mode (the default)
# -d	Don't rebuilt crscope.out
# -k	Ignore (cscope compatiblity)
#
# If -d is specified AND crscope.out exists, read it in.
# Else:
#    If files are specified on the command line, read those files.
#    Else if crscope.files exist, read the files it contains.
#    Else read in all .cr files in the current directory.
#    Write crscope.out.

def main
  debug = false
  dont_rebuild = false
  server = false
  tabsize = 8

  OptionParser.parse do |parser|
    parser.banner = "Usage: crscope [options] [filenames]"
    parser.on("-v",
	      "--verbose",
	      "Print debug messages") { debug = true }
    parser.on(
      "-d",
      "--dont-rebuild",
      "Don't rebuild database") { dont_rebuild = true }
    parser.on(
      "-t tabsize",
      "--tabsize=LEN",
      "Specifies the size of a tab in source files") {|size| tabsize = size.to_i }
    parser.on(
      "-k",
      "Ignored for cscope compatibility") { }
    parser.on(
      "-l",
      "Line-oriented interface") { server = true }
    parser.on(
      "-h",
      "--help",
      "Show this help") do
        STDERR.puts parser
	exit 0
      end
    parser.invalid_option do |flag|
      STDERR.puts "ERROR: #{flag} is not a valid option."
      STDERR.puts parser
      exit 1
    end
  end

  index = Index.new(debug, tabsize)
  filenames = ARGV
  if dont_rebuild && File.exists?("crscope.out")
    puts "Reading crscope.out" if debug
    index.read_database("crscope.out")
  elsif filenames.size > 0
    index.parse_files(filenames)
  elsif File.exists?("crscope.files")
    index.parse_files(File.read_lines("crscope.files", chomp: true))
  else
    puts "No files specified and crscope.files doesn't exist.  Exiting."
    exit 1
  end
  index.print if debug
  index.write_database("crscope.out") unless dont_rebuild
  if server
    unless File.exists?("crscope.out")
      puts "crscope.out does not exist.  Run crscope without -l and -d to create it."
      exit 1
    end
    index.line_interface
  else
    index.curses_interface
  end
end

main
