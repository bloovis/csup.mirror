# crscope - cscope-like cross-reference tool for Crystal
#
# I've used cscope for decades to examine C source trees.  I also added
# commands to my MicroEMACS editor to use cscope without leaving
# the editor.  This program implements a subset of the cscope features,
# but for Crystal source trees.  MicroEMACS only needs the
# line-oriented interface of cscope, but I also implemented
# the curses-oriented interface for using outside of an editor.
#
# The four search types that crscope implements are:
#
# 0 - Find any symbol
# 1 - Find a method definition
# 4 - Find a string (non-regexp)
# 6 - Perform an egrep search.
# 7 - Perform a file search.
#
# Crscope parses files you specify on the command line, or can
# parse the files that you list in crscope.files.  It writes the
# results of its parsing to crscope.out, which is plain-text file.

require "option_parser"
require "compiler/crystal/syntax"

require "../src/pipe"
require "../src/supcurses"

class Config
  def self.bool(sym)
    false
  end
end

# Search types in crscope have the same integer values as search types in cscope.

SEARCH_TYPES = {
  :symbol   => 0,	# Find this Crystal symbol
  :function => 1,	# Find this function definition
  :calledby => 2,	# Find functions called by this function
  :calling  => 3,	# Find functions calling this function
  :text     => 4,	# Find this text string (non-regexp)
  :grep     => 6,	# Find this grep -E pattern
  :file     => 7,	# Find this file
  :assign   => 9,	# Find assignments to this symbol
}

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

  # Pad a string on the left with spaces.
  def pad_left(width : Int32)
    pad = width - self.size
    " " * pad + self
  end

  # Pad a string on the right with spaces.
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

  TYPES = {
    :class  => "C",
    :module => "M",
    :def    => "D",
    :macro  => "m",
    :lib    => "L",
    :struct => "S",
    :fun    => "F",
    :assign => "A",
    :call   => "c",
    :end    => "E",
    :symbol => "s",
  }

  # Class used to record a name definition.
  class Def
    property type : Symbol
    property name : String
    property lineno : Int32
    property indent : Int32	# lexical indentation, used only for Ruby
    property context : String

    def initialize(@type, @name, @lineno, @indent, @context)
      #puts "Def.initialize #{@type},#{@name},#{@lineno},#{@indent},#{@context}"
    end
  end

  # Class used to process nodes in the abstract syntax tree
  # for a parsed Crystal program.
  class Visitor < Crystal::Visitor
    @filename : String
    @content : String
    @scope : Array(String)
    @defs : Array(String)
    @fdefs : FileDefs

    def initialize(@filename, @content, @fdefs)
      @scope = [] of String
      @defs = [] of String
    end

    def single_name(type : Symbol, node) : String
      name = (@scope + [node.name]).join(".")
      lineno = get_lineno(node)
      column = get_column(node)
      context = get_context(node)
      @fdefs.add_name(type, name, lineno, column, context)
      #puts [type, name, location, context].join("#")
      #puts "key for #{type} is #{TYPES.key_for?(type)}"
      return name.to_s
    end

    def unscoped_single_name(type : Symbol, node) : String
      name = node.name
      lineno = get_lineno(node)
      column = get_column(node)
      context = get_context(node)
      @fdefs.add_name(type, name, lineno, column, context)
      #puts [type, name, location, context].join("#")
      #puts "key for #{type} is #{TYPES.key_for?(type)}"
      return name.to_s
    end

    def multi_name(type : Symbol, node) : String
      name = node.name.names.last
      names = (@scope + node.name.names).join(".")
      lineno = get_lineno(node)
      column = get_column(node)
      context = get_context(node)
      @fdefs.add_name(type, name, lineno, column, context)
      #puts [type, names, location, context].join("#")
      #puts "key for #{type} is #{TYPES.key_for?(type)}"
      return names
    end
      
    def visit(node : Crystal::ClassDef)
      name = multi_name(:class, node)
      @scope << node.name.names.last
      true
    end

    def visit(node : Crystal::ModuleDef)
      name = multi_name(:module, node)
      @scope << name
      true
    end

    def visit(node : Crystal::Def)
      name = single_name(:def, node)
      @defs << name
      true
    end

    def visit(node : Crystal::Macro)
      single_name(:macro, node)
      true
    end

    def visit(node : Crystal::LibDef)
      name = single_name(:lib, node)
      @scope << name
      true
    end

    def visit(node : Crystal::StructOrUnionDef)
      name = single_name(:struct, node)
      @scope << name
      true
    end

    def visit(node : Crystal::FunDef)
      single_name(:fun, node)
      true
    end

    def visit(node : Crystal::Expressions)
      #puts "visit(expressions): node #{node.class}"
      true
    end

    def visit(node : Crystal::ASTNode)
      #puts "visit(astnode): node #{node.class}"
      true
    end

    def visit(node : Crystal::Assign)
      lineno = get_lineno(node)
      column = get_column(node)
      context = get_context(node)
      target = node.target
      if target.is_a?(Crystal::Path)
	name = target.names.join(".")
      elsif target.is_a?(Crystal::Var) || target.is_a?(Crystal::InstanceVar)
	name = target.name
      else
	name = "<unknown>"
      end
      @fdefs.add_name(:assign, name, lineno, column, context)
      #puts ["A", name, location, context].join("#")
      true
    end

    def visit(node : Crystal::Path)
      names = node.names.join("::")
      #puts "visit(path): names #{names}"
      true
    end

    def visit(node : Crystal::Call)
      # Don't bother recording operator calls like + or == .
      if node.name =~ /^[@_A-Za-z0-9]+$/
	unscoped_single_name(:call, node)
      end

      #puts "visit(call): name #{node.name}, scope #{@scope.join('.')}"
      #location = node.location
      #if location
	#filename = location.filename || "<unknown>"
	#puts "  filename #{filename}, line #{location.line_number}"
      #end
      #obj = node.obj
      #if obj
	#puts "  obj #{obj.class}"
      #end
      true
    end

    def visit(node : Crystal::InstanceVar | Crystal::ReadInstanceVar | Crystal::ClassVar |
                     Crystal::Global | Crystal::OpAssign | Crystal::MultiAssign |
		     Crystal::Var)
      #puts "visit(other): node #{node.class}"
    end

    def end_visit(node : Crystal::Def)
      #defs = @defs.join("/")
      #puts "end_visit Def, defs = #{defs}"
      name = @defs.pop?
      if name
	@fdefs.add_name(:end, name, 0, 0, "")
	#puts ["E", name, "", ""].join("#")
      end
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef |
    		  Crystal::CStructOrUnionDef | Crystal::LibDef)
      #puts "end_visit: node #{node.class}"
      return unless node.location
      @scope.pop?
    end

    def get_lineno(node) : Int32
      location = node.location
      if location
	return location.line_number
      else
	return 1
      end
    end

    def get_column(node) : Int32
      location = node.location
      if location
	return location.column_number
      else
	return 1
      end
    end

    def get_context(node) : String
      node.to_s.lines.first
    end

  end	# Class Visitor

  property filename = ""

  # Ephemeral stack of modules and classes, used only during parsing.
  property class_stack = [] of Def

  # Permanent record of definitions, using fully qualified names.
  property records = [] of Def

  property debug = false
  property tabsize = 8

  def initialize(@filename : String, @debug = false, @tabsize = 8)
  end

  # Read the Ruby source file and use our ugly heuristics to find the
  # definitions of classes, modules, C libraries and functions,
  # aliases, methods, and constants.
  def parse_ruby_file
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
	  # Classes, modules, and C libraries.
	  space = $1
	  kind = $2
	  name = $3.gsub("::", ".")
	  one_line = false

	  # One-liner class defs don't need to be pushed on the stack.
	  if line =~ /;\s*end\s*$/
	    one_line = true
	  end

	  type = case kind
	    when "class" then :class
	    when "module" then :module
	    when "lib" then :lib
	    else :symbol
	  end
	  add_class(type, name, space.display_size(tabsize), lineno, space.size, line.strip,
		    one_line)
	elsif line =~ /^(\s*)abstract\s*class\s+([\w:]+)/
	  # Astract classes have to be handled separately due to regex issues.
	  space = $1
	  name = $2.gsub("::", ".")
	  one_line = false
	  if line =~ /;\s*end\s*$/
	    one_line = true
	  end
	  add_class(:class, name, space.display_size(tabsize), lineno, space.size, line.strip,
		    one_line)
	elsif line =~ /^(\s*)def\s+(self\.)?(\w+)/
	  # Methods.
	  add_name(:def, $3, lineno, $1.size, line.strip)
	elsif line =~ /^(\s*)end(\s|$)/
	  # If this is the "end" of a module or class, pop the enclosed modules or
	  # classes off of the stack.
	  pop_defs($1.display_size(tabsize))
	elsif line =~ /^(\s*)(fun|alias)\s+(\w+)/
	  # C library functions and class aliases.
	  add_name(:symbol, $3, lineno, $1.size, line.strip)
	elsif line =~ /^(\s*)([A-Z_]+)\s*=/
	  # Constants.
	  add_name(:symbol, $2, lineno, $1.size, line.strip)
	end
	lineno += 1
      end
    end
  end

  # Read the Crystal source file and parse it using the compiler's
  # parser/visitor library.
  def parse_crystal_file
    content = File.read(@filename)
    visitor = Visitor.new(@filename, content, self)
    parser = Crystal::Parser.new(content)
    parser.filename = filename
    node = parser.parse
    node.accept(visitor)
  end

  def dprint(s : String)
    puts s if @debug
  end

  # If this is a one-liner class definition, add it to the permanent record of names.
  # Otherwise push it on the stack, so that we can handle nested classes.
  def add_class(type : Symbol, name : String, indent : Int32, lineno : Int32, column : Int32,
		context : String, one_line = false)
    dprint "add_class: type #{type}, name #{name}, indent #{indent}, lineno #{lineno}, one_line #{one_line}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    unless one_line
      class_stack.push (Def.new(:class, name, lineno, indent, context))
    end
    records.push (Def.new(type, full_name, lineno, column, context))
  end

  # Add a name to the permanent record of names.
  def add_name(type : Symbol, name : String, lineno : Int32, column : Int32, context : String)
    dprint "add_name: name #{name}, lineno #{lineno}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    records.push (Def.new(type, full_name, lineno, column, context))
  end

  # Pop the most recent class definition after seeing an "end" statement
  # of the same indentation.
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
      f.puts [TYPES[r.type], r.name, "#{@filename}:#{r.lineno}:#{r.indent+1}",
	      r.context].join("#")
    end
  end
end

# Class defining an entry field in the search form.
class Entry
  property prompt : String	# prompt string
  property row : Int32		# line number on screen
  property type : Symbol	# key to SEARCH_TYPES
  property buf : String		# entry buffer
  property leftcol : Int32 	# starting column for entry
  property fillcols : Int32	# number of columns to right of prompt

  def initialize(@prompt, @row, @type)
    @buf = ""
    @leftcol = prompt.size + 1
    @fillcols = Ncurses.cols - @leftcol
    Ncurses.mvaddstr @row, 0, @prompt
  end

end

class Index
  property fdefs = Hash(String, FileDefs).new	# indexed by filename
  property debug = false
  property tabsize = 8
  property nrows = 0		# total number of lines in terminal window
  property result_rows = 0 	# space for results at top of screen
  property results = [] of Result
  property ignore_case = false
  property qualified = false

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
      if filename =~ /\.cr/
	fdef.parse_crystal_file
      else
	fdef.parse_ruby_file
      end
      fdef.print(STDOUT) if debug
      add_file(fdef)
    end
  end

  def read_database(infile : String)
    File.open(infile, "r") do |f|
      f.each_line(chomp: true) do |line|
        splits = line.split("#")
	kind = splits[0]
	type = FileDefs::TYPES.key_for?(kind) || :symbol
	name = splits[1]
	file = splits[2]
	context = splits[3]

	file_splits = file.split(":")
	filename = file_splits[0]
	lineno = file_splits[1].to_i
	indent = file_splits[2].to_i - 1
	unless fdef = fdefs[filename]?
	  fdef = FileDefs.new(filename, debug, tabsize)
	  fdefs[filename] = fdef
	end
	fdef.records.push(FileDefs::Def.new(type, name, lineno, indent, context))
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

  def search(name : String, search_type : Symbol, partial_match = false) : Array(Result)
    if @ignore_case
      name = name.downcase
    end
    results = [] of Result
    fdefs.each do |filename, fdef|
      in_method = false
      fdef.records.each do |r|
        # If we are searching for methods called by a named method,
	# and we're in that method:
	# - save calls in the results
	# - ignore all other symbols
	if search_type == :calledby && in_method
	  if r.type == :call
	    results.push(Result.new(filename, r.name, r.lineno,r.context))
	  elsif r.type == :end
	    in_method = false
	  end
	  next
        end

        # End records aren't "real" symbols; they're just the marker
	# for the end of a method, so skip them.
	if r.type == :end
	  in_method = false
	  next
	end

	# If searching for a function definition, ignore
	# any non-def records.
	next if search_type == :function && r.type != :def

	# See if this record matches the provided name.
	found_name = nil
        rname = @ignore_case ? r.name.downcase : r.name
	if partial_match
	  # partial_match means the name in the symbol table only has to start
	  # with the name being searched, i.e., not match it entirely.
	  if @qualified
	    # We must include any classname qualifications in the match.
	    if rname.starts_with?(name)
	      found_name = r.name
	    end
	  else
	    # We can ignore any or all classname qualifications in the match.
	    regexp = Regex.new("^.*[.]?(#{name}[^\.]*)$")
	    match = regexp.match(rname)
	    if match && match[1]?
	      found_name = match[1]
	    end
	  end
        elsif @qualified
	  if rname == name
	    # @qualfied means the names must be identical.
	    found_name = r.name
	  end
	else
	  # @qualified is false, which means the name being searched doesn't need to match
	  # any of the class name qualifications of the name in the symbol table.
	  regexp = Regex.new("(^|\\.)#{name}$")
	  match = regexp.match(rname)
	  if match
	    found_name = r.name
	  end
	end

	# There is a match.  If this is an ordinary symbol or method search,
	# add the record to the results.  If this is a search for methods
	# called by the named method, set the flag indicating that we must
	# collect calls until the end of the method is seen.
	next unless found_name
	if search_type == :calledby
	  if r.type == :def
	    in_method = true
	  end
	elsif search_type == :calling
	  if r.type == :call
	    results.push(Result.new(filename, found_name, r.lineno,r.context))
	  end
	elsif search_type == :assign
	  if r.type == :assign
	    results.push(Result.new(filename, found_name, r.lineno,r.context))
	  end
	else
	  results.push(Result.new(filename, found_name, r.lineno,r.context))
	end
      end
    end
    return results
  end

  def grepsearch(name : String, fixed = false) : Array(Result)
    results = [] of Result
    # Get the list of filenames, either from crscope.files,
    # or from the filenames listed in crscope.out.
    if File.exists?("crscope.files")
      filenames = File.read_lines("crscope.files", chomp: true)
    else
      filenames = fdefs.each.map {|filename, fdef| filename}
    end
    filenames.each do |filename|
      if fixed
	# Search for a fixed string, not a regexp.
	options = ["-F", "-n"]
      else
	# Search for a regexp.
	options = ["-E", "-n"]
      end
      if @ignore_case
	options.push("-i")
      end
      pipe = Redwood::Pipe.new("grep", options + [name, filename])
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
      search_type = SEARCH_TYPES.key_for?(line[0].to_i) || :symbol
      search_term = line[1..]
      results = [] of Result
      case search_type
      when :symbol, :function
        results = search(search_term, search_type)
      when :text
	results = grepsearch(search_term, true)
      when :grep
	results = grepsearch(search_term, false)
      when :file
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
    Ncurses.move 1, 0
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
    Ncurses.mvaddstr 1, 0,
      "  " +
      "File".pad_right(flen) + " " +
      "Name".pad_right(nlen) + " " +
      "Line".pad_right(llen)

    # Display the results with fields padded nicely.
    (0..@result_rows-1).each do |i|
      Ncurses.move i + 2, 0
      Ncurses.clrtoeol
      if i < shown
	r = @results[i + offset]
	Ncurses.mvaddstr i + 2, 0,
	  "#{char_for(i)} " +
	  "#{Path[r.filename].basename.pad_right(flen)} " +
	  "#{r.name.pad_right(nlen)} " +
	  "#{r.line.to_s.pad_left(llen)} " +
	  "#{r.context}"
      end
    end
    return shown
  end

  # Perform a search appropriate for this entry's type (function, regexp, file).
  def entry_search(entry : Entry, partial_match = false) : Array(Result)
    results = [] of Result
    s = entry.buf
    case entry.type
    when :symbol, :function, :calling, :calledby, :assign
      results = search(s, entry.type, partial_match: partial_match)
    when :text
      results = grepsearch(s, true)
    when :grep
      results = grepsearch(s, false)
    when :file
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
      show_status("Environment variable EDITOR not defined!")
    end
  end

  def show_status(s : String)
    Ncurses.mvaddstr(0, 0, s)
    Ncurses.clrtoeol
  end
    
  def toggle_ignore_case
    @ignore_case = ! @ignore_case
    show_status("Caseless mode is now " + (@ignore_case ? "ON" : "OFF"))
  end

  def toggle_qualified
    @qualified = ! @qualified
    show_status("Qualified mode is now " + (@qualified ? "ON" : "OFF"))
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
	more = @results.size - (offset + shown)
	reload = false
	if @results.size > @result_rows - 2
	  Ncurses.mvaddstr @result_rows + 1, 0,
	    "* Lines #{offset + 1}-#{offset + shown} of #{rsize}, " +
	    "#{more} more - press Space to go " +
	    (more == 0 ? "to the start" : "forward") +
	    ", Backspace to go back *"
	end
      end
      Ncurses.move i + 2, 0
      c = Ncurses.getkey
      next if c == ""
      case c
      when " "
        offset += shown
	if offset >= rsize
	  offset = 0
	end
	reload = true
      when "C-c"
        toggle_ignore_case
      when "C-q"
	toggle_qualified
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

  # Prompt the user to enter a string for this entry, and return the last character
  # typed (Enter, Up, Down, or C-d). The passed-in completion proc
  # returns the longest possible suffix for the current entry buffer.

  def get_entry(e : Entry, &block : Proc(String)) : String
    Ncurses.mvaddstr(e.row, 0, e.prompt)
    Ncurses.move(e.row, e.leftcol)
    Ncurses.clrtoeol
    Ncurses.curs_set 1
    Ncurses.refresh

    pos = e.buf.size
    done = false
    aborted = false
    lastc = ""
    while true
      # Redraw the e.buf buffer.
      if e.buf.size >= e.fillcols
	# Answer is too big to fit on screen.  Just show the right portion that
	# does fit.
	Ncurses.mvaddstr(e.row, e.leftcol, e.buf[e.buf.size-e.fillcols..e.buf.size-1])
        Ncurses.move(e.row, Ncurses.cols - 1)
      else
        Ncurses.mvaddstr(e.row, e.leftcol, e.buf + (" " * (e.fillcols - e.buf.size)))
        Ncurses.move(e.row, e.leftcol + pos)
      end
      Ncurses.refresh

      c = Ncurses.getkey
      next if c == ""
      case c
      when "C-a"
        pos = 0
      when "C-c"
	toggle_ignore_case
      when "C-q"
	toggle_qualified
      when "C-e"
        pos = e.buf.size
      when "Left", "C-b"
        if pos > 0
	  pos -= 1
	end
      when "Right", "C-f"
        if pos < e.buf.size
	  pos += 1
	end
      when "C-h", "Delete"
        if !(c == "C-h" && pos == 0)
	  if c == "C-h"
	    pos -= 1
	  end
	  left = (pos == 0) ? "" : e.buf[0..pos-1]
	  right = (pos >= e.buf.size - 1) ? "" : e.buf[pos+1..]
	  e.buf = left + right
	end
      when "C-k"
        if pos == 0
	  e.buf = ""
	else
	  e.buf = e.buf[0..pos-1]
	end
      when "C-u"
        e.buf = ""
	pos = 0
      when "?"
        if e.type != :grep
	  suffix = yield
	  e.buf = e.buf.insert(pos, suffix)
	  pos += suffix.size
	end
      when "C-m", "C-d", "Up", "Down", "C-g", "C-n", "C-p", "C-i"
        return c
      else
	if c.size == 1
	  e.buf = e.buf.insert(pos, c)
	  pos += 1
	end
      end
      lastc = c
    end
  end

  def curses_interface
    Redwood.start_cursing
    Ncurses.curs_set 1

    @nrows = Ncurses.rows
    @results = [] of Result

    # Add the four entry fields.
    entries = [] of Entry
    row = @nrows - 1
    entries.push Entry.new("Find this symbol:",  row-7, :symbol)
    entries.push Entry.new("Find this method:",  row-6, :function)
    entries.push Entry.new("Find calls by this method:", row-5, :calledby)
    entries.push Entry.new("Find calls to this method:", row-4, :calling)
    entries.push Entry.new("Regexp search:",     row-3, :grep)
    entries.push Entry.new("Non-regexp search:", row-2, :text)
    entries.push Entry.new("File search:",       row-1, :file)
    entries.push Entry.new("Find assignments to this symbol:", row, :assign)
    @result_rows = @nrows - entries.size - 3	# leave room for status line, blank line, and prompt line

    entry_number = 0
    done = false
    until done
      entry = entries[entry_number]
      c = get_entry(entry) do
        # User hit ?, so try to do a completion.
	# First, get all partial matches.
	@results = entry_search(entry, partial_match: true)
	show_results(0)
	if @results.size == 0
	  show_status "Could not find #{entry.buf}"
	end

	# Find the longest possible match for the string entered so far.
	s = entry.buf
	prefix = s
	suffix = ""
	longest = s
	if @results.size > 0 && entry.type != :file
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
      # Enter - display matches
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
	  show_status "Could not find #{entry.buf}"
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
