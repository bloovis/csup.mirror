module Redwood

# `Pipe` provides a simplified mechanism for running an external program
# in a pipe. Create a pipe to a program using `Pipe#new`.  Then start interacting
# with the program using `start`.  The block you pass to `start` will
# then use the following methods to send and receive data to/from the program:
# * Transmit data to the program's stdin using `transmit`.
# * Receive data from the program's stdout using `receive`.
# * Receive data from the program's stderr using `receive_stderr`.
class Pipe
  class PipeError < Exception
  end

  property success = false
  property input_closed = false
  property output_closed = false
  property error_closed = false
  @process : Process?

  # Starts the program *prog* with arguments *args*, with
  # its stdin, stdout, and stderr available to the caller.
  def initialize(prog : String, args : Array(String), shell = false)
    begin
      @process = Process.new(prog,
			     shell ? nil : args,
                             input: Process::Redirect::Pipe,
                             output: Process::Redirect::Pipe,
                             error: Process::Redirect::Pipe,
			     shell: shell)
      @success = true
    rescue IO::Error
      @success = false
    end
  end

  # Yields this Pipe object to the block, then waits for the
  # program to exit, and returns its exit code.
  def start : Int32	# returns exit status
    yield self
    wait
  end

  # Yields the file handle connected to the program's stdin,
  # then closes that file handle when the block returns.
  def transmit(&)
    if p = @process
      yield p.input
      p.input.close
    end
    @input_closed = true
  end

  # Yields the file handle connected to the program's stdout,
  # then closes that file handle when the block returns.
  def receive(&)
    if p = @process
      yield p.output
      p.output.close
    end
    @output_closed = true
  end

  # Yields the file handle connected to the program's stderr,
  # then closes that file handle when the block returns.
  def receive_stderr(&)
    if p = @process
      yield p.error
      p.error.close
    end
    @error_closed = true
  end

  # Waits for the program to exit, closes all file handles,
  # and returns the program's exit code.
  def wait : Int32
    if p = @process
      p.input.close unless @input_closed
      p.output.close unless @output_closed
      p.error.close unless @error_closed
      p.wait.exit_code
    else
      -1
    end
  end

  # Runs notmuch with the specified arguments and stdin data; used by `Notmuch.run`.
  # Parameters:
  # * *prog*: name of the program to run (always "notmuch").
  # * *args*: the list of command line arguments to notmuch
  # * *check_status*: if true, raises an exception if notmuch fails
  # * *check_stderr*: if true, raises an exception if notmuch wrote to stderr
  # * *input*: optional string to pass to notmuch's standard input.
  #
  # `run` returns the output of notmuch as a string.
  def self.run(prog : String,			# name of program to run
	       args : Array(String),		# arguments
               check_status : Bool = true,	# raise exception if command fails
	       check_stderr : Bool = true,	# raise exception if command wrote to stderr
	       input : String = "") : String	# data to feed to standard input
    pipe = Pipe.new(prog, args)
    unless pipe.success
      raise PipeError.new("Failed to execute #{prog}")
    end

    stdout_str = ""
    stderr_str = ""

    exit_status = pipe.start do |p|
      if input.size != 0
	p.transmit {|f| f << input}
      end
      p.receive {|f| stdout_str = f.gets_to_end}
      if check_stderr
	p.receive_stderr {|f| stderr_str = f.gets_to_end}
      end
    end

    if (check_status && exit_status != 0) || (check_stderr && !stderr_str.empty?)
      raise PipeError.new("Failed to execute #{prog} #{args}: exitcode=#{exit_status}, stderr=#{stderr_str}")
    end
    stdout_str
  end
end	# Pipe

end	# Redwood
