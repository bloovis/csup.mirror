
require "./singleton"

module Redwood

# `LabelManager` is a singleton class that keeps track of all labels used in messages, and
# also provides lists of reserved labels.
#
# It is similar to `LabelManager` in Sup, except that labels are stored
# as Strings, not Symbols, and label collections are Set(String).  Also,
# labels are no longer saved in the file `labels.txt`. Instead, we
# rely on Notmuch knowing all the labels in use.
class LabelManager
  singleton_class

  # Provides a set of labels that have special semantics.
  RESERVED_LABELS = Set.new([ :starred, :spam, :draft, :unread, :killed,
			      :sent, :deleted, :inbox, :attachment, :forwarded,
			      :replied ].map(&.to_s))

  # Provides labels that will typically be hidden from the user.
  HIDDEN_RESERVED_LABELS = Set.new([ :starred, :unread, :attachment, :forwarded,
				     :replied ].map(&.to_s))

  # Provides a list of labels seen in Notmuch at startup.
  @labels = Set(String).new

  # Provides a list of labels added after startup.
  @new_labels = Set(String).new

  # Queries Notmuch for a list of all labels that are not in `RESERVED_LABELS`,
  # and saves them in `@labels`.
  def initialize
    singleton_pre_init

    Notmuch.all_tags.each {|t| @labels << t unless RESERVED_LABELS.includes?(t) }

    singleton_post_init
  end

  # Returns true if the label *l* is new, i.e., was added after startup.
  def new_label?(l : String | Symbol)
    @new_labels.includes?(l.to_s)
  end
  singleton_method new_label?, l

  # Returns all labels, both user-defined and system, ordered
  # nicely and converted to pretty strings.
  def all_labels
    RESERVED_LABELS + @labels
  end
  singleton_method all_labels

  # Returns all user-defined labels, ordered
  # nicely and converted to pretty strings.
  def user_defined_labels
    @labels
  end
  singleton_method user_defined_labels

  # Reverses the label(symbol)-to-string mapping, for convenience.
  # If the label is reserved, capitializes it.
  def string_for(l : String | Symbol) : String
    ls = l.to_s
    if RESERVED_LABELS.includes? ls
      ls.capitalize
    else
      ls
    end
  end
  singleton_method string_for

  # Adds a new new label *t* to the list.  This has no effect on Notmuch.
  def << (t : String | Symbol)
    ts = t.to_s
    unless @labels.includes?(ts) || RESERVED_LABELS.includes?(ts)
      @labels << ts
      @new_labels << ts
    end
  end
  def self.<<(t)
    self.instance.<< t
  end

  # Deletes the label *t* from the list.  This has no effect on Notmuch.
  def delete(t : String | Symbol)
    ts = t.to_s
    if @labels.delete(ts)
    end
  end
  singleton_method delete, t

end

end
