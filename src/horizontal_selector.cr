require "./widget.cr"
require "./util.cr"

module Redwood

# `HorizontalSelector` represents a line showing a multi-value selector.
# The user can select one of the values by moving the cursor left or right.
# This is used by two Modes: `EditMessageMode` and `ReplyMode`.
class HorizontalSelector
  class UnknownValue < StandardError; end

  property label : String
  property changed_by_user : Bool
  property selection : Int32

  # Create a selector whose values are *vals*, with the corresponding
  # labels *labels*.
  def initialize(@label, vals : Array(String), labels : Array(String), 
		 base_color=:horizontal_selector_unselected_color,
		 selected_color=:horizontal_selector_selected_color)
    @vals = vals
    @labels = labels
    @base_color = base_color
    @selected_color = selected_color
    @selection = 0
    @changed_by_user = false
  end

  # Makes the value *val* the currently selected value.  Raises
  # an `UnknownValue` exception if *val* is not one of the possible
  # values for this selector.
  def set_to(val)
    if i = @vals.index(val)
      @selection = i
    else
      raise UnknownValue.new(val.inspect)
    end
  end

  # Returns true if the current value can be set to *val*.
  def can_set_to?(val)
    !@vals.index(val).nil?
  end

  # Returns the currently selected values.
  def val; @vals[@selection] end

  # Constructs the line displaying the current state of the selector.
  def line(width=nil) : WidgetArray
    label =
      if width
        @label.pad_left(width)
      else
        "#{@label} "
      end

    l = WidgetArray.new
    l << {@base_color, label}
    @labels.each_with_index do |label, i|
      if i == @selection
	l << {@selected_color, label}
      else
	l << {@base_color, label}
      end
      l << {@base_color, "  "}
    end
    l << {@base_color, ""}
    return l
  end

  # Moves the current selection to the left by one, or to the last
  # if already at the first.
  def roll_left
    @selection = (@selection - 1) % @labels.size
    @changed_by_user = true
  end

  # Moves the current selection to the right by one, or to the first
  # if already at the last.
  def roll_right
    @selection = (@selection + 1) % @labels.size
    @changed_by_user = true
  end
end

end
