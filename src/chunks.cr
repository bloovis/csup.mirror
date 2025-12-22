# encoding: UTF-8

require "./shellwords"
require "./message"

module Redwood

# `Chunk` is the base class for Chunks. It should never be instantiated directly.
# Classes derived from `Chunk` define all the "chunks" that a message is parsed into.
#
# Chunks are used by ThreadViewMode to render a message. Chunks
# are used for both MIME stuff like attachments, for csup's parsing of
# the message body into text, quote, and signature regions, and for
# notices like "this message was decrypted" or "this message contains
# a valid signature"---basically, anything we want to differentiate
# at display time.
#
# A chunk can be inlineable, expandable, or viewable. If it's
# inlineable, #color and #lines are called and the output is treated
# as part of the message text. This is how Text and one-line Quotes
# and Signatures work.
#
# If it's not inlineable but is expandable, #patina_color and
# #patina_text are called to generate a "patina" (a one-line widget,
# basically), and the user can press enter to toggle the display of
# the chunk content, which is generated from #color and #lines as
# above. This is how Quote, Signature, and most widgets
# work. Exandable chunks can additionally define #initial_state to be
# :open if they want to start expanded (default is to start collapsed).
#
# If it's not expandable but is viewable, a patina is displayed using
# #patina_color and #patina_text, but no toggling is allowed. Instead,
# if #view! is defined, pressing enter on the widget calls view! and
# (if that returns false) #to_s. Otherwise, enter does nothing. This
#  is how non-inlineable attachments work.
#
# Independent of all that, a chunk can be quotable, in which case it's
# included as quoted text during a reply. Text, Quotes, and mime-parsed
# attachments are quotable; Signatures are not.
class Chunk
  # The chunk type (:attachment, :text, :quote, :sig, :enclosure).
  property type : Symbol

  # The lines of text for the chunk.
  property lines = [] of String

  # The chunk state (:closed, :open)
  property initial_state = :closed

  # Color of text lines; used only if expandable? is true.
  property color = :text_color
  
  # Patina color; used only if expandable? is true.
  property patina_color = :text_color

  # Patina text.
  property patina_text = "Chunk"

  # True if the chunk is quotable (i.e., can be quoted in replies).
  property quotable = false
  def quotable?; @quotable end

  # True if the chunk is inlineable (i.e., can be treated as
  # part of the message text).
  def inlineable?; false end
  
  # True if the chunk is expandable (i.e., can be toggles to/from
  # a one-line patina representation).
  def expandable?; false end

  # True if the chunk is viewable as text.
  def viewable?; false end

  # Saves the attachment type.
  def initialize(@type)
  end
end

# Defines a chunk representing a single email attachment.
class AttachmentChunk < Chunk
  # The part of the message for this attachment.
  property part : Message::Part

  # The message as a whole.
  property message : Message

  # Initializes an attachment chunk.  If *decode* is true, it uses mime-decode
  # the attachment. Then it breaks up the attachment into lines and stores
  # them in `@lines`.
  def initialize(@part : Message::Part, @message : Message, decode = false)
    super(:attachment)

    @color = :text_color
    @patina_color = :attachment_color
    @initial_state = :open

    text = ""
    if decode
      success = HookManager.run("mime-decode") do |pipe|
	pipe.transmit do |f|
	  f.puts(@part.content_type)
	  f << @part.content
	end
	pipe.receive do |f|
	  text = f.gets_to_end
	end
      end
      if !success || text.size == 0
	#text = "mime-decode hook not implemented for part #{@part.id}, #{@part.content_type}.\n"
      end
    end

    if text && text.size > 0
      @lines = text.gsub("\r\n", "\n").gsub(/\t/, "        ").gsub(/\r/, "").split("\n")
      @quotable = true
      @patina_text = "Attachment: #{part.filename} (#{lines.length.pluralize "line"})"
    else
      @patina_text = "Attachment: #{part.filename} (#{part.content_type}; #{part.content_size.to_human_size})"
      @lines = [] of String
    end
    if filename != "" && !filename =~ /^c?sup-attachment-/
      @message.add_label :attachment
    end
  end

  # Always false, because attachments are not intended to be viewed inline with message text.
  def inlineable?; false end

  # True if the attachment was decoded into viewable text lines.
  def viewable?
    #STDERR.puts "attachment lines.size #{lines.size}"
    lines.size == 0
  end

  # True if the attachment is expandable, which is the case only if the
  # attachment is *not* viewable.
  def expandable?
    #STDERR.puts "attachment part #{part.content_type}, expandable #{!viewable?}, initial state #{initial_state}"
    !viewable?
  end

  # The filename of attachment.
  def filename
    @part.filename
  end

  # The filename of the attachment, with shell metacharacters replaced by '_'.
  def safe_filename
    Shellwords.escape(filename).gsub("/", "_")
  end

  # Attempts to use the mime-view hook to view the attachment outside of csup.
  # This might be used to view a PDF attachment in an external PDF viewer, for example.
  # Returns true if successful, or false otherwise.
  def view! : Bool
    Notmuch.view_part(@message.id, @part.id, @part.content_type)
  end

  # Saves the attachment to the file *filename*.
  def save(filename : String)
    Notmuch.save_part(@message.id, @part.id, filename)
  end

  # Returns the attachment as a string, which only works if the attachment
  # was able to be decoded into lines of text.
  def to_s
    # What should we use for raw_content?  Does it make sense to use part.content
    # when that could be binary data like JPEG?
    @lines.join("\n") # || @raw_content
  end
end

# `TextChunk` represents a message chunk consisting of lines of plain text.
class TextChunk < Chunk
  # Creates a text chunk for the array of lines in *@lines*.
  # Removes all but one trailing empty line.
  def initialize(@lines)
    super(:text)
    # trim off all empty lines except one
    while @lines.length > 1 && @lines[-1] =~ /^\s*$/ && @lines[-2] =~ /^\s*$/
      @lines.pop
    end

    @color = :text_color
  end

  # A `TextChunk` is always inlineable.
  def inlineable?; true end

  # A `TextChunk` is always inlineable.
  def quotable?; true end

  # A `TextChunk` is not expandable, since it's expanded by default.
  def expandable?; false end

  # A `TextChunk` is always indexable.  This method is not used in csup.
  def indexable?; true end

  # A `TextChunk` is always inlineable.
  def viewable?; false end
end

# `QuoteChunk` represents a sequence of quoted lines in a message (i.e., lines
# preceded by "> " characters.
class QuoteChunk < Chunk
  def initialize(@lines)
    super(:quote)
    @patina_color = :quote_patina_color
    @patina_text = "(#{@lines.size} quoted lines)"
    @color = :quote_color
  end

  # True if the quote is inlineable, i.e., consists of a single line.
  # Otherwise it is expandable.
  def inlineable?; @lines.length == 1 end

  # A quote is always quotable in replies.
  def quotable?; true end

  # True if if the quote is expandable, i.e., consists of more than one line.
  def expandable?; !inlineable? end

  # A quote is not viewable by an external program.
  def viewable?; false end
end

# `SignatureChunk` represents the signature lines at the end of a message.
class SignatureChunk < Chunk
  def initialize(@lines)
    super(:sig)
    @patina_color = :sig_patina_color
    @patina_text = "(#{lines.size}-line signature)"
    @color = :sig_color
  end

  # True if the signature is inlineable, i.e., consists of a single line.
  # Otherwise it is expandable.
  def inlineable?; @lines.length == 1 end

  # A signature is never quotable in replies.
  def quotable?; false end

  # True if if the signature is expandable, i.e., consists of more than one line.
  def expandable?; !inlineable? end

  # A signature is not viewable by an external program.
  def viewable?; false end
end

# `EnclosureChunk` represents an enclosed message.
class EnclosureChunk < Chunk
  
  # Copies the more important message headers to the chunk lines,
  # but to save room on the screen, does not copy the message text itself.
  def initialize(p : Message::EnclosurePart)
    super(:enclosure)

    @initial_state = :closed

    @lines << ""
    @lines << "From: #{p.from}"
    @lines << "To: #{p.to}"
    unless p.cc.size == 0
      @lines << "Cc: #{p.cc}"
    end
    @lines << "Date: #{p.date}"
    @lines << "Subject: #{p.subject}"
    @lines << ""

    @patina_color = :generic_notice_patina_color
    @patina_text = "Begin enclosed message sent on #{p.date}"
    @color = :quote_color
  end

  # An enclosure is not inlineable.
  def inlineable?; false end

  # An enclosure is never quotable in replies.
  def quotable?; false end

  # An enclosure is expandable, because there is more than one line.
  def expandable?; true end

  # Not used anywhere.
  def indexable?; true end

  # An enclosure is not viewable by an external program.
  def viewable?; false end
end

end	# Redwood
