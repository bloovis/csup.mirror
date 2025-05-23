# Create message thread list by parsing the result of:
#  notmuch search --format=text "query"
#  notmuch show --body=true --format=json --include-html --body=true "thread:ID1 or thread:ID2 or ..."
# where the result of `notmuch search` is passed to `notmuch show`.

require "json"
require "./notmuch"
require "./person"
require "./time"
require "./chunks"
require "./singleton"

# Construct a random name for an attachment
def random_name
  "csup-attachment-#{Time.now.to_i}-#{rand 10000}"
end

module Redwood

# By caching message thread data, we can reduce the size and number of
# "notmuch search" queries.  Once a thread is loaded into the cache,
# it doesn't need to be reloaded unless one of the following happens:
# - The user wants to view the thread's body contents (see load_body).
# - The user deletes a draft message, forcing notmuch to recreate its containing thread.

class ThreadCache
  singleton_class

  def initialize
    singleton_pre_init
    @cache = Hash(String, ThreadData).new
    singleton_post_init
  end

  def get(threadid : String) : ThreadData
    @cache[threadid]
  end
  singleton_method get, threadid

  def add(thread : ThreadData)
    @cache[thread.id] = thread
  end
  singleton_method add, thread

  def cached?(threadid : String)
    @cache.has_key?(threadid)
  end
  singleton_method cached?, threadid
end

# A message is actually a tree of messages: it can have multiple children.
class Message

  # Ordinary text part
  class Part
    property id : Int32
    property content_type : String
    property filename : String
    property content : String
    property content_size : Int32
    property level : Int32

    def initialize(@id, @content_type, @filename, @content, @content_size, @level)
    end
  end

  # message/rfc822 part (enclosed message)
  class EnclosurePart < Part
    property from : String
    property to : String
    property cc : String
    property subject : String
    property date : String
    property body : String

    def initialize(id, level, @from, @to, @cc, @date, @subject, @body)
      super(id, "message/rfc822", random_name, "", 0, level)
    end
  end

  ## some utility methods
  RE_PATTERN = /^((re|re[\[\(]\d[\]\)]):\s*)+/i
  def self.subj_is_reply?(s); s =~ RE_PATTERN; end
  def self.reify_subj(s); subj_is_reply?(s) ? s : "Re: " + s; end

  QUOTE_PATTERN = /^\s{0,4}[>|\}]/
  BLOCK_QUOTE_PATTERN = /^-----\s*Original Message\s*----+$/
  SIG_PATTERN = /(^(- )*-- ?$)|(^\s*----------+\s*$)|(^\s*_________+\s*$)|(^\s*--~--~-)|(^\s*--\+\+\*\*==)/
  MAX_SIG_DISTANCE = 15 # lines from the end
  SNIPPET_LEN = 80

  alias Parts =  Array(Part)
  alias Headers = Hash(String, String)

  property id : String = ""
  property parent : Message | Nil
  property children : Array(Message)
  property headers : Headers
  property labels : Set(String)
  property parts : Parts		# index to this array may not match part.id!
  property timestamp : Int64
  property filename : String
  property date_relative : String
  property thread : ThreadData?		# containing thread
  property from : Person
  property to : Array(Person)
  property cc : Array(Person)
  property bcc : Array(Person)
  property subj = "<no subject>"
  property date : Time
  property chunks = Array(Chunk).new
  property have_snippet = false
  property snippet = ""
  property dirty_labels = false
  property refs = Array(String).new

  property recipient_email : String?
  property replyto : Person?
  property list_address : Person?

  # If a JSON result from "notmuch show" is provided in `data`, parse it
  # to fill in the message fields.  Otherwise use some empty default values, and
  # use `data` as the message ID.
  def initialize(data = nil)
    @parent = nil
    @children = Array(Message).new
    @headers = Headers.new
    @labels = Set(String).new
    @parts = Parts.new
    @timestamp = 0
    @filename = ""
    @date_relative = ""
    if data.nil?
      @id = "<dummy>"
    elsif data.is_a?(String)
      @id = data
    else
      parse_message(data)
    end

    # Fill in some properties for Sup compatibility.
    if @headers.has_key?("From")
      @from = Person.from_address(headers["From"])
    else
      @from = Person.new("nobody", "nobody@example.com")
    end
    if @headers.has_key?("Subject")
      @subj = @headers["Subject"].gsub(/\s+/, " ").strip
    else
      @subj = "<no subject>"
    end
    @to = Person.from_address_list(@headers["To"]?)
    @cc = Person.from_address_list(@headers["Cc"]?)
    @bcc = Person.from_address_list(@headers["Bcc"]?)

    @refs = (@headers["References"]? || "").scan(/<(.+?)>/).map { |x| x[1] }
    if replyto = @headers["Reply-To"]?
      @replyto = Person.from_address(replyto)
    end
    @recipient_email = @headers["X-Original-To"]? || @headers["Delivered-To"]?
    #@list_address = @headers["List-Post"]?
    list_post = @headers["List-Post"]?
    @list_address = if list_post
      address = if list_post =~ /mailto:(.*?)[>\s$]/
        $1
      elsif list_post =~ /@/
        list_post # just try the whole thing
      end
      address && Person.from_address(address)
    #elsif @headers["x-mailing-list"]?
    #  Person.from_address @headers["x-mailing-list"]
    end


    @date = Time.unix(@timestamp)

    walktree do |msg, i|
      msg.find_chunks
    end
  end

  def dirty_labels?; @dirty_labels end

  def add_child(child : Message)
    @children << child
    child.parent = self
  end

  # Convert a header name into a customary (quasi-standardized) form, where each
  # of the dash-separated parts is capitalized, except for ID, which is all uppercase.
  def fix_header_name(name : String) : String
    name.split("-").map do |x|
      n = x.capitalize
      n == "Id" ? "ID" : n
    end.join("-")
  end

  def add_header(name : String, value : String)
    @headers[fix_header_name(name)] = value
  end

  def add_tag(name : String)
    @labels.add(name)
  end

  # For Sup compatibility
  def clear_dirty_labels
    @dirty_labels = false
  end

  def has_label?(s : Symbol | String)
    @labels.includes?(s.to_s)
  end

  def add_label(l : Symbol | String)
    l = l.to_s
    return if @labels.includes? l
    @labels.add(l)
    @dirty_labels = true
  end

  def remove_label(l : Symbol | String)
    l = l.to_s
    return unless @labels.includes? l
    @labels.delete l
    @dirty_labels = true
  end

  def labels=(l : Set(String))
    return if @labels == l
    @labels = l
    @dirty_labels = true
  end

  def is_list_message?; !@list_address.nil?; end
  def is_draft?; has_label?(:draft) end
  def draft_filename
    raise "not a draft" unless is_draft?
    @filename
  end

  def raw_header : String
    ret = ""
    begin
      File.open(@filename) do |f|
        while (l = f.gets) && (l != "")
	  ret += l + "\n"
	end
      end
    rescue e
      BufferManager.flash e.message || "Unable to open #{@filename}"
    end
    return ret
  end

  def raw_message : String
    ret = ""
    begin
      File.open(@filename) do |f|
        ret = f.gets_to_end
      end
    rescue e
      BufferManager.flash e.message || "Unable to open #{@filename}"
    end
    return ret
  end

  def sync_back_labels
    Message.sync_back_labels [self]
  end

  def self.sync_back_labels(messages : Array(Message))
    dirtymessages = messages.select{|m| m && m.dirty_labels?}
    Notmuch.tag_batch(dirtymessages.map{|m| {"id:#{m.id}", m.labels.to_a}})
    dirtymessages.each(&.clear_dirty_labels)
  end

  def quotable_body_lines : Array(String)
    chunks.select { |c| c.quotable? }.map { |c| c.lines }.flatten
  end

  def quotable_header_lines
    ["From: #{@from.full_address}"] +
      (@to.empty? ? [] of String : ["To: " + @to.map { |p| p.full_address }.join(", ")]) +
      (@cc.empty? ? [] of String : ["Cc: " + @cc.map { |p| p.full_address }.join(", ")]) +
      (@bcc.empty? ? [] of String : ["Bcc: " + @bcc.map { |p| p.full_address }.join(", ")]) +
      ["Date: #{@date.to_rfc2822}",
       "Subject: #{@subj}"]
  end

  # Code for constructing parts
  def add_part(id : Int32, ctype : String, filename : String, s : String,
	       content_size : Int32, level = 0)
    if filename == ""
      newname = random_name
      if ctype =~ /text\/html/
	filename = newname + "." + "html"
      elsif ctype =~ /image\/(.*)/
	filename = newname + "." + $1
      else
	filename = newname
      end
    end
    @parts << Part.new(id, ctype, filename, s, content_size, level)
  end

  def find_part(&b : Part -> Bool) : Part?
    @parts.each do |p|
      if b.call(p)
	return p
      end
    end
    return nil
  end

{% if flag?(:TEST) %}
  def print(level = 0, print_content = false)
    prefix = "  " * level
    puts "#{prefix}Message:"
    puts "#{prefix}  id: #{@id}"
    puts "#{prefix}  filename: #{@filename}"
    parent = @parent
    if parent
      puts "#{prefix}  parent id: #{parent.id}"
    end

    puts "#{prefix}  timestamp: #{@timestamp} (#{Time.unix(@timestamp)})"
    puts "#{prefix}  tags: #{@labels.to_a.join(",")}"
    puts "#{prefix}  date_relative: #{@date_relative}"

    puts "#{prefix}  headers:"
    headers.each do |k,v|
      puts "#{prefix}    #{k} = #{v}"
    end

    @parts.each do |p|
      colon = (print_content ? ":" : "")
      puts "#{prefix}  Part ID #{p.id}, content type #{p.content_type}, filename '#{p.filename}'#{colon}\n"
      if p.content == ""
	puts "#{prefix}  Content missing!"
      elsif print_content
        puts p.content
      end
    end

    if @children.size > 0
      puts "#{prefix}  Children:"
      @children.each do |child|
	child.print(level + 2, print_content)
      end
    end
  end
{% end %}

  # Walk the the tree of messages, passing each message and its depth
  # to the block.
  private def do_walk(msg : Message, depth : Int32, &b : Message, Int32 -> _)
    b.call msg, depth
    msg.children.each do |child|
      do_walk(child, depth + 1, &b)
    end
  end

  def walktree(&b : Message, Int32 -> _)
   do_walk(self, 0) {|msg, depth| b.call msg, depth}
  end

  def append_chunk(chunks : Array(Chunk), lines : Array(String), type : Symbol)
    #STDERR.puts "append_chunk: type #{type}, #lines = #{lines.size}"
    return if lines.empty?
    chunk = case type
            when :text
              TextChunk.new(lines)
            when :quote, :block_quote
              QuoteChunk.new(lines)
            when :sig
              SignatureChunk.new(lines)
            else
              raise "unknown chunk type: #{type}"
            end
    if chunk
      chunks << chunk
    end
  end

  ## parse the lines of text into chunk objects.  the heuristics here
  ## need tweaking in some nice manner. TODO: move these heuristics
  ## into the classes themselves.
  def text_to_chunks(lines : Array(String), encrypted = false) : Array(Chunk)
    state = :text # one of :text, :quote, or :sig
    chunks = [] of Chunk
    chunk_lines = [] of String
    nextline_index = -1

    lines.each_with_index do |line, i|
      #STDERR.puts "text_to_chunks: line #{i} = '#{line.chomp}'"
      if i >= nextline_index
        # look for next nonblank line only when needed to avoid O(n²)
        # behavior on sequences of blank lines
        if nextline_index = lines[(i+1)..-1].index { |l| l !~ /^\s*$/ } # skip blank lines
          nextline_index += i + 1
          nextline = lines[nextline_index]
        else
          nextline_index = lines.length
          nextline = nil
        end
      end

      case state
      when :text
        newstate = nil

        ## the following /:$/ followed by /\w/ is an attempt to detect the
        ## start of a quote. this is split into two regexen because the
        ## original regex /\w.*:$/ had very poor behavior on long lines
        ## like ":a:a:a:a:a" that occurred in certain emails.
        if line =~ QUOTE_PATTERN || (line =~ /:$/ && line =~ /\w/ && nextline =~ QUOTE_PATTERN)
	  #STDERR.puts "in quote, line = '#{line}', nextline = '#{nextline}'"
          newstate = :quote
        elsif line =~ SIG_PATTERN && (lines.length - i) < MAX_SIG_DISTANCE && !lines[(i+1)..-1].index { |l| l =~ /^-- $/ }
          newstate = :sig
        elsif line =~ BLOCK_QUOTE_PATTERN
          newstate = :block_quote
        end

        if newstate
          append_chunk(chunks, chunk_lines, state)
          chunk_lines = [line]
          state = newstate
        else
          chunk_lines << line
        end

      when :quote
        newstate = nil

        if line =~ QUOTE_PATTERN || (line =~ /^\s*$/ && nextline =~ QUOTE_PATTERN)
          chunk_lines << line
        elsif line =~ SIG_PATTERN && (lines.length - i) < MAX_SIG_DISTANCE
          newstate = :sig
        else
          newstate = :text
        end

        if newstate
          append_chunk(chunks, chunk_lines, state)
          chunk_lines = [line]
          state = newstate
        end

      when :block_quote, :sig
        chunk_lines << line
      end

      if !@have_snippet && state == :text && (@snippet.empty? || @snippet.length < SNIPPET_LEN) && line !~ /[=\*#_-]{3,}/ && line !~ /^\s*$/
	#STDERR.puts "old snippet for #{@id}: '#{@snippet}'"
        @snippet ||= ""
        @snippet += " " unless @snippet.empty?
        @snippet += line.gsub(/[\r\n]/, "").strip
        oldlen = @snippet.length
        @snippet = @snippet[0 ... SNIPPET_LEN].chomp
        @snippet += "..." if @snippet.length < oldlen
	#STDERR.puts "new snippet for #{@id}: '#{@snippet}'"
        @snippet_contains_encrypted_content = true if encrypted
      end
    end
    @have_snippet = true

    ## final object
    append_chunk(chunks, chunk_lines, state)
    chunks
  end

  # Find all chunks for this message.
  def find_chunks
    @chunks = [] of Chunk
    plain_level = -1
    @parts.each do |p|
      if plain_level == -1 && p.content_type == "text/plain" && p.content_size > 0
	plain_level = p.level
	lines = p.content.lines
	#STDERR.puts "find_chunks: calling text_to_chunks for msg #{@id}, part #{p.id}"
	@chunks = @chunks + text_to_chunks(lines)
      elsif p.is_a?(EnclosurePart) # p.content_type == "message/rfc822"
        @chunks << EnclosureChunk.new(p)
	@chunks << TextChunk.new(p.body.split("\n"))
      else
	@chunks << AttachmentChunk.new(p, self, p.level != plain_level)
      end
    end
  end

  # Get a string value from a hash, or the empty string if
  # there is no such value, or the value is not a string.
  def string_from_hash(h : Hash, key : String)
    if h.has_key?(key)
      if val = h[key].as_s?
	return val
      end
    end
    return ""
  end

  # Functions for parsing messages.

  def parse_part(p : JSON::Any, level = 0)
    part = p.as_h?
    if part
      #STDERR.puts "part: #{part.inspect}"
      return unless part["id"]?
      id =      part["id"].as_i
      ctype =   part["content-type"].as_s.downcase
      if part.has_key?("filename")
	filename = part["filename"].as_s
      else
	filename = ""
      end
      if part.has_key?("content-length")
	content_length = part["content-length"].as_i
      else
	content_length = 0
      end
      #STDERR.puts "about to get content for part #{id}, ctype #{ctype}"
      if part.has_key?("content")
	content = part["content"].as_s?
	if content
	  #STDERR.puts "Adding content for part #{id}, content:\n---\n#{content}\n---\n"
	  add_part(id, ctype, filename, content, content.size, level)
	else
	  content = part["content"].as_a?
	  if content
	    #STDERR.puts "Part #{id} has array content, type #{ctype}"
	    if ctype == "message/rfc822"
	      return unless content.size > 0
	      #STDERR.puts "enclosure has non-zero content size"
	      return unless msg = content[0].as_h?
	      #STDERR.puts "enclosure has content hash"
	      return unless hdr = msg["headers"].as_h?
	      #STDERR.puts "enclosure has headers"
	      return unless body_array = msg["body"].as_a?
	      return unless body_array.size > 0
	      return unless body = body_array[0].as_h?
	      #STDERR.puts "enclosure has body"
	      subject = string_from_hash(hdr, "Subject")
	      from = string_from_hash(hdr, "From")
	      to = string_from_hash(hdr, "To")
	      cc = string_from_hash(hdr, "Cc")
	      date = string_from_hash(hdr, "Date")
	      body_text = string_from_hash(body, "content")
	      #STDERR.puts "Adding EnclosurePart, id #{id}, body '#{body_text}'"
	      @parts << EnclosurePart.new(id, level, from, to, cc, date, subject, body_text)
	    else
	      content.each do |c|
		#STDERR.puts "Adding nested content, level #{level + 1}"
		parse_part(c, level + 1)
	      end
	    end
	  end
	end
      else
	add_part(id, ctype, filename, "", content_length)	# attachment with no content in JSON
      end
    end
  end

  def single_message(msg_info : Hash(String, JSON::Any))
    @id = msg_info["id"].as_s

    tags = msg_info["tags"].as_a?
    if tags
      tags.each { |tag| add_tag(tag.as_s)}
    end

    if msg_info.has_key?("timestamp")
      timestamp = msg_info["timestamp"].as_i64?
      if timestamp
	@timestamp = timestamp
      end
    end

    headers = msg_info["headers"].as_h?
    if headers
      headers.each do |k, v|
	key = k
	if key
	  value = v.as_s?
	  if value
	    add_header(key, value)
	  end
	end
      end
    end

    if msg_info.has_key?("body")
      body = msg_info["body"].as_a?
      if body
	body.each do |p|
	  parse_part(p)
	end
      end
    end

    if msg_info.has_key?("filename")
      filenamelist = msg_info["filename"].as_a?
      if filenamelist
	@filename = filenamelist[0].as_s
      end
    end

    if msg_info.has_key?("date_relative")
      date = msg_info["date_relative"].as_s?
      if date
	@date_relative = date
      end
    end
  end

  def parse_message(json : JSON::Any)
    msgarray = json.as_a
    #STDERR.puts "parse_message #{json}, msgarray size #{msgarray.size}"
    msg_info = msgarray[0].as_h?
    if msg_info
      single_message msg_info
    else
      @id = "<null>"
    end
    #STDERR.puts "parse_message: children #{msgarray[1]}"
    children = msgarray[1].as_a?
    if children
      children.each do |child|
        #STDERR.puts "parse_message: child #{child}"
	c = Message.new(child)
	add_child(c)
      end
    end
  end

end	# Message

alias ThreadEach = Tuple(Message, Int32, Message?)	# thread, depth, parent

# ThreadData contains the information about the messages in a single thread.
# This is the object that is stored in the thread cache (ThreadCache).
# There should be only one copy of a ThreadData object for any given thread.
# We ensure this through the use of the MsgThread object, which refers to
# to a ThreadData object in the cache via the thread ID.

class ThreadData
  include Enumerable(ThreadEach)

  property id = ""
  property msg : Message?
  property size = 0
  property subj = "<no subject>"
  property size_widget = ""
  property date_widget = ""

  def initialize(json : JSON::Any, @id)
    #STDERR.puts "MsgData: json #{json}"
    # There usually seems to be only one message in the array, but occasionally
    # there is more than one.  Treat the messages after the first one as children
    # of the first message.
    msglist = json.as_a
    #STDERR.puts "MsgData: msglist size #{msglist.size}"
    m = Message.new(msglist[0])
    if msglist.size > 1
      msglist[1..].each do |json|
        #STDERR.puts "MsgData: adding unexpected child"
        child = Message.new(json)
	m.add_child child
      end
    end
    @dirty_labels = false
    if m
      @subj = m.subj
      set_msg(m)
    end

    @size_widget = case self.size
      when 1
        ""
      else
        "(#{self.size})"
      end
    @date_widget = self.date.to_local.to_nice_s
  end

  # Reload message thread data with body and html content.  This involves
  # using notmuch search and show to get the thread data, and replacing
  # the current top level message, which doesn't have body and html content.
  def load_body
    ts = ThreadList.new(@id, offset: 0, limit: 1, body: true, force: true)
    if ts
      if (thread = ts.threads[0]?) && (m = thread.msg)
	# In each message in the thread, if the "Reply-To" header is present,
	# replace @from with that person.  This allows the thread view mode
	# to show the actual sender in messages from mailing lists.
	thread.each do |m, d, p|
	  if replyto = m.replyto
	    m.from = replyto
	  end
	end

	# Set the thread top level message, which copies the entire thread tree.
	set_msg(m)
      end
    end
  end

  # Replace the top level message with the specified message.
  # Then set the thread for each message in the tree, and update
  # the thread size and date widget.
  def set_msg(m : Message)
    @msg = m
    @size = 0
    m.walktree do |msg, depth|
      msg.thread = self
      @size += 1
    end
    @date_widget = self.date.to_local.to_nice_s
  end

  def to_s : String	# for creating debug messages
    if m = @msg
      mid = m.id
    else
      mid = "<unknown>"
    end
    "thread #{self.object_id}, msg id:#{mid}"
  end

  def messages : Array(Message)
    a = Array(Message).new
    if m = @msg
      m.walktree { |msg, depth| a << msg }
    end
    return a
  end

  def apply_label(t); each { |m, d, p| m && m.add_label(t) }; end
  def remove_label(t); each { |m, d, p| m && m.remove_label(t) }; end

  def toggle_label(label)
    if has_label? label
      remove_label label
      false
    else
      apply_label label
      true
    end
  end

  def has_label?(t); any? { |m, d, p| m && m.has_label?(t) }; end

  def labels
    l = Set(String).new
    each {|m, d, p| l = l + m.labels}
    return l
  end

  def labels=(l : Set(String))
    each {|m, d, p| m.labels = l}
  end

  def date
    t = 0
    each { |m, d, p| t = [t, m.timestamp].max}
    return Time.unix(t)
  end

  def snippet : String
    with_snippets = Array(Message).new
    each do |m, d, p|
      if m && m.snippet != ""
	with_snippets << m
      end
    end
    first_unread = with_snippets.select { |m| m.has_label?(:unread) }.sort_by(&.date).first?
    return first_unread.snippet if first_unread
    last_read = with_snippets.sort_by(&.date).last?
    return last_read.snippet if last_read
    ""
  end

  def first : Message?
    @msg
  end

{% if flag?(:TEST) %}
  def print(print_content = false)
    if m = @msg
      puts "Thread object id #{self.object_id}"
      m.print(level: 0, print_content: print_content)
    else
      puts "Thread is empty!"
    end
  end
{% end %}

  # This allows MsgData.map to be used.  We can't yield inside
  # the walktree block, so we have to save the results of walktree, then
  # yield them afterwards.
  def each
    if m = @msg
      results = Array(ThreadEach).new
      m.walktree do |msg, depth|
        results << {msg, depth, msg.parent}
      end
      results.each {|r| yield r}
    end
  end

  def authors : Array(Person)
    map { |m, d, p| m.from }.compact.uniq
  end

  def direct_participants : Array(Person)
    map { |m, d, p| [m.from] + m.to }.flatten.compact.uniq
  end

  def participants : Array(Person)
    map { |m, d, p| [m.from] + m.to + m.cc + m.bcc }.flatten.compact.uniq
  end

  def latest_message : Message?
    return nil unless latest = @msg
    each do |m, d, p|
      if m && m.date > latest.date
	latest = m
      end
    end
    return latest
  end

  def save
    Message.sync_back_labels messages
  end
end	# ThreadData

# This is the message thread object that is returned to all modes that
# use message threads, i.e. ThreadViewMode and modes derived from ThreadIndexMode.
# It refers to the actual cached thread data (ThreadData) via the thread ID.
# This indirection ensures that there is only one copy of ThreadData
# for any given thread.

class MsgThread
  property id : String

  def initialize(@id)
  end

  def cache : ThreadData
    ThreadCache.get(id)
  end

  forward_missing_to cache
end

# This is the list of threads that results from any given notmuch search.
# It is responsible for placing found threads in the thread cache.
# The `force` parameter to the constructor has this meaning:
# - If true, all found threads should be stored in the cache, overwriting
#   any cached data that may already be in the cache
# - If false, only threads that are not already in the cache are loaded.

class ThreadList
  property threads = Array(MsgThread).new
  property query = ""

  def initialize(@query, offset : Int32, limit : Int32, body = false, force = false)
    debug "ThreadList.new: query #{@query}, offset #{offset}, limit #{limit}"
    if query
      run_notmuch_show(@query, offset: offset, limit: limit, body: body, force: force)
    end
  end

  # Run 'notmuch search' and 'notmuch show' to obtain the threads for the
  # specified query string.
  def run_notmuch_show(query : String, offset : Int32? = nil, limit : Int32? = nil,
		       body = false, force = false)
    @query = query

    # First, get the list of threads matching the query.  If body is true,
    # we're trying to load the body of a message we've already found,
    # so set --exclude=false to ignore the exclude tags in .notmuch-config.
    #STDERR.puts "run_notmuch_show: search query '#{query}', body #{body}"
    thread_ids = Notmuch.search(query, exclude: !body, offset: offset, limit: limit)
    if thread_ids.size == 0
      #puts "run_notmuch_show: query '#{query}' produced no results"
      return
    end

    # Make a list of threads that must be loaded into the cache:
    # - all threads, if force is true; or
    # - only threads not already in cache, if force is false
    ids_to_load = thread_ids.select {|id| force || !ThreadCache.cached?(id)}

    # Construct a show query from the list of threads and obtain
    # the JSON output.  Add resulting threads to the cache.
    if ids_to_load.size > 0
      show_query = ids_to_load.join(" or ") + " and (#{query})"
      #STDERR.puts "run_notmuch_show: show query '#{show_query}'"
      json = Notmuch.show(show_query, body: body, html: body)
      parse_json(json, ids_to_load)
    end

    # Make an array of MsgThread objects.  At this point,
    # we can assume that all required thread data objects
    # have been loaded into the cache.
    thread_ids.each {|id| @threads << MsgThread.new(id)}
  end

  def parse_json(json : JSON::Any, thread_ids : Array(String))
    #puts "parse_json #{json}"
    results = json.as_a?
    if results
      if results.size != thread_ids.size
	raise "thread list should contain #{thread_ids.size} items, but has #{results.size} items!"
      end
      results.each_with_index do |result, i|
	ThreadCache.add(ThreadData.new(result, thread_ids[i]))
      end
    else
      STDERR.puts "results is a #{json.class.name}, expected array"
    end
  end

  # Find a thread in this thread list that matches the `other` thread.
  # The match is based on the thread IDs.  This is used by
  # get_update_thread in thread index modes, because of the possibility
  # that two different thread objects in diffent modes may refer
  # to the same thread.
  def find_thread(other : MsgThread) : MsgThread?
    #STDERR.puts "find_thread: searching for thread id #{other.id}"
    threads.each do |t|
      #STDERR.puts "find_thread: checking thread id #{t.id}"
      if t.id == other.id
	return t
      end
    end
    return nil
  end

{% if flag?(:TEST) %}
  def print(print_content = false)
    puts "ThreadList:"
    @threads.each_with_index do |thread, i|
      puts "----"
      puts "Thread #{i}:"
      thread.print(print_content: print_content)
    end
  end
{% end %}

end	# ThreadList

end	# Redwood
