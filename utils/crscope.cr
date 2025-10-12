require "option_parser"
require "../src/pipe"

# Provide a String method that gives the display length,
# taking into account the display size of a tab.
class String
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
end

# Class used to record all name defintions for a single file.
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

  # Ephemeral stacks of definitions used only during parsing.
  property class_stack = [] of Def
  property method_stack = [] of Def

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
      f.each_line do |line|
	#puts "line #{lineno}: #{line.strip}"
	if line =~ /^(\s*)(class|module|lib)\s+(\w+)/
	  add_class($3, $1.display_size(tabsize), lineno, $1.size, line.strip)
	elsif line =~ /^(\s*)def\s+(\w+)/
	  add_method($2, $1.display_size(tabsize), lineno, $1.size, line.strip)
	elsif line =~ /^(\s*)end(\s|$)/
	  pop_defs($1.display_size(tabsize))
	elsif line =~ /^(\s*)(fun|alias)\s+(\w+)/
	  add_fun($3, lineno, $1.size, line.strip)
	end
	lineno += 1
      end
    end
  end

  def dprint(s : String)
    puts s if @debug
  end

  def add_class(name : String, indent : Int32, lineno : Int32, column : Int32, context : String)
    dprint "add_class: name #{name}, indent #{indent}, lineno #{lineno}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    class_stack.push (Def.new(name, lineno, indent, context))
    records.push (Def.new(full_name, lineno, column, context))
  end

  def add_method(name : String, indent : Int32, lineno : Int32, column : Int32, context : String)
    dprint "add_method: name #{name}, indent #{indent}, lineno #{lineno}"
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    method_stack.push (Def.new(name, lineno, indent, context))
    records.push (Def.new(full_name, lineno, column, context))
  end

  def add_fun(name : String, lineno : Int32, column : Int32, context : String)
    full_name = (class_stack.map {|d| d.name} + [name]).join(".")
    records.push (Def.new(full_name, lineno, column, context))
  end

  def pop_defs(indent : Int32)
    dprint "pop_defs: indent #{indent}"
    while class_stack.size > 0 && indent <= class_stack[-1].indent
      d = class_stack.pop
      dprint "Popped class #{d.name}"
    end
    while method_stack.size > 0 && indent <= method_stack[-1].indent
      m = method_stack.pop
      dprint "Popped method #{m.name}"
    end
  end

  def print(f : IO)
    dprint "FileDefs.print"
    records.each do |r|
      f.puts "#{r.name}|#{@filename}:#{r.lineno}:#{r.indent+1}|#{r.context}"
    end
  end
end

class Index
  property fdefs = Hash(String, FileDefs).new	# indexed by filelname
  property debug = false
  property tabsize = 8

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

  def search(name : String, all_results = true)
    primary_results = [] of String
    secondary_results = [] of String
    fdefs.each do |filename, fdef|
      fdef.records.each do |r|
        if r.name == name
	  primary_results.push("#{filename} #{r.name} #{r.lineno} #{r.context}")
	elsif all_results
	  regexp = Regex.new("(^|\\.)#{name}$")
	  match = regexp.match(r.name)
	  if match
	    secondary_results.push("#{filename} #{r.name} #{r.lineno} #{r.context}")
	  end
	end
      end
    end
    total_results = primary_results.size + secondary_results.size
    if total_results > 0
      STDOUT.puts "cscope: #{total_results} lines"
      primary_results.each {|s| STDOUT.puts s}
      secondary_results.each {|s| STDOUT.puts s}
    else
      STDOUT.puts "no results"
    end
  end

  def grepsearch(name : String)
    results = [] of String
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
	      results.push("#{filename} <unknown> #{lineno} #{context}")
	    end
	  end
	end
      end
    end
    total_results = results.size
    if total_results > 0
      STDOUT.puts "cscope: #{total_results} lines"
      results.each {|s| STDOUT.puts s}
    else
      STDOUT.puts "no results"
    end
  end

  def line_interface
    while true
      STDOUT.print ">> "
      STDOUT.flush
      line = STDIN.gets
      return if line.nil?
      search_type = line[0]
      search_term = line[1..]
      case search_type
      when '0'
        search(search_term, all_results: true)
      when '1'
        search(search_term, all_results: false)
      when '6'
	grepsearch(search_term)
      else
	puts "Unknown search type #{search_type}"
      end
    end
  end
	
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
      "Show this help") { puts parser }
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
    index.line_interface if server
  end
end

main
