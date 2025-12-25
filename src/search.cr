
require "./singleton"
require "./supcurses"

module Redwood

# `SearchManager` is a singleton class that allows the user to save searches
# and give them names.  The Crystal version here is much simpler than the Ruby
# version in sup-notmuch. That's because the predefinedqueries stuff appeared
# to be a relic of the Xapian-enabled sup and wasn't used. So I removed it entirely.
class SearchManager
  singleton_class

  # Exception that is raised by #expand if an infinite recursion
  # seems to have occurred.
  class ExpansionError < StandardError; end

  # Reads the saved searches file (`~/.csup/searches.txt`), and
  # creates the hash mapping search names to search query strings.
  # Also defines a built-in named search called "inbox".
  def initialize(fn : String)
    singleton_pre_init

    @fn = fn
    @searches = Hash(String, String).new
    if File.exists? fn
      File.each_line(fn) do |l|
        l =~ /^([^:]*): (.*)$/ || raise "can't parse #{fn} line #{l.inspect}"
        @searches[$1] = $2
      end
    end
    @modified = false

    @predefined_searches = { "inbox" => "tag:inbox" }
    @predefined_searches.each do |k,v|
      @searches[k] = v
    end

    singleton_post_init
  end

  # Returns a list of the names of all searches.
  def all_searches
    return @searches.keys.sort
  end
  singleton_method all_searches

  # Returns the query string for the search named *name*.
  def search_string_for(name : String)
    return @searches[name]?
  end
  singleton_method search_string_for, name

  # Returns true if *name* is a valid name for a search, i.e., consists
  # only of letters, numbers, underscores, or dashes.
  def valid_name?(name : String)
    name =~ /^[\w-]+$/
  end
  singleton_method valid_name?, name

  # Returns a help string to remind users what constitutes a valid search name.
  def name_format_hint
    "letters, numbers, underscores and dashes only"
  end
  singleton_method name_format_hint

  # Adds a new search whose name is *name* and whose query string is *search_string*.
  # Does not override any predefined searches.
  def add(name : String, search_string : String)
    return unless valid_name? name
    if @predefined_searches.has_key? name
      warn "cannot add search: #{name} is already taken by a predefined search"
      return
    end
    @searches[name] = search_string
    @modified = true
  end
  singleton_method add, name, search_string

  # Renames a named search from *old* to *new*.
  def rename(old : String, new : String)
    return unless @searches.has_key? old
    if @predefined_searches.has_key?(old)
      warn "cannot rename search: old name #{old} is already taken by a predefined search"
      return
    end
    if @predefined_searches.has_key?(new)
      warn "cannot rename search: new name #{new} is already taken by a predefined search"
      return
    end
    search_string = @searches[old]
    delete(old) if add(new, search_string)
  end
  singleton_method rename, old, new

  # Changes the search query for the search named *name* to *search_string*.
  def edit(name : String, search_string : String)
    return unless @searches.has_key? name
    if @predefined_searches.has_key? name
      warn "cannot edit predefined search: #{name}."
      return
    end
    @searches[name] = search_string
    @modified = true
  end
  singleton_method edit, name, search_string

  # Deletes the search named *name*.
  def delete(name : String)
    return unless @searches.has_key? name
    if @predefined_searches.has_key? name
      warn "cannot delete predefined search: #{name}."
      return
    end
    @searches.delete name
    @modified = true
  end
  singleton_method delete, name

  # Returns the query string *search_string* with all references to named
  # searches of the form `{name}` replaced by their associated query strings.
  # Raises `ExpansionError` if the size of the expanded string is so large
  # as to indicate the possiblity of an infinite recursion.
  def expand(search_string : String)
    expanded = search_string
    until (matches = expanded.scan(/\{([\w-]+)\}/).map{|rd| rd[1]}).empty?
      if !(unknown = matches - @searches.keys).empty?
        error_message = "Unknown \"#{unknown.join("\", \"")}\" when expanding \"#{search_string}\""
      elsif expanded.size >= 2048
        error_message = "Check for infinite recursion in \"#{search_string}\""
      end
      if error_message
        warn error_message
        raise ExpansionError.new(error_message)
      end
      matches.each do |n|
        if @searches.has_key?(n)
          expanded = expanded.gsub("{#{n}}", "(#{@searches[n]})")
	end
      end
    end
    return expanded
  end
  singleton_method expand, search_string

  # Saves all user-created named searches to the file `~/.csup/searches.txt`.
  def save
    return unless @modified
    File.open(@fn, "w") do |f|
      (@searches.keys - @predefined_searches.keys).sort.each do |k|
	f.puts "#{k}: #{@searches[k]}"
      end
    end
    @modified = false
  end
  singleton_method save
end

end
