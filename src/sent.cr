require "./singleton"
require "./notmuch"

module Redwood

# `SentManager` is a singleton class whose sole purpose is
# to save a sent message in the Notmuch mailstore.
class SentManager
  singleton_class

  property folder = ""

  # Saves the Notmuch folder name for sent messages, which is "sent"
  # by default, but can be overridden by the `:sent_folder` value in
  # `~/.csup/config.yaml`.
  def initialize(folder : String)
    singleton_pre_init
    @folder = folder
    singleton_post_init
  end

  # Writes a message to the Notmuch "sent" folder.  Passes
  # an `IO` object to the block, to which the block must write the
  # contents of the message.
  def self.write_sent_message(&block : IO -> _) : Bool
    stored = false
    ##::Thread.new do
      debug "store the sent message"
      stored = Notmuch.insert(instance.folder, &block)
    ##end #Thread.new
    stored
  end

end # class

end # module
