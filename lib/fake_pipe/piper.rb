module FakePipe
  # This class cooridinates between all the text blocks.
  # The class is initialized with some input io, an output io, and an adapter.
  #
  # ## Adapter
  # An adapter is created by creating a module directly under fake_pipe. The
  # module must respond to `text_blocks` which will return all the `TextBlock`
  # classes needed to call `on_config` and `on_cell`.
  #
  # ## General IO Flow
  # The `run` method is probably the most interesting. It streams in `each_line`
  # of the input `io` and will output either the same line or the parsed line
  # from the `TextObject#parse`. It's the responsibility of the TextBlock to
  # extract relevant table, column, cell information. This class will make
  # keep track of when to mutate cell.
  #
  # Most lines from `io` should be passed directly to the `outputter`
  class Piper
    attr_accessor :io, :configs, :outputter, :text_blocks

    # @param [String] adapter should be a module file directly under the 'fake_pipe' path
    def initialize(io:, outputter:, adapter:)
      self.configs = {}
      self.io = io
      self.outputter = outputter
      register_adapter(adapter)
    end

    def register_adapter(adapter)
      adapter_module = "fake_pipe/#{adapter}"
      require adapter_module
      adapter_class = adapter_module.camelize.constantize
      self.text_blocks = adapter_class.text_blocks.map do |block_class|
        block_class.new(delegate: self)
      end

      # AnyBlock is a catch all and needs to come last.
      text_blocks << AnyBlock.new(delegate: self)
    end

    def run
      # used to track which text_block is currently in use
      current_block = text_blocks.last
      io.each_line do |line|
        if current_block.end_text?(line)
          output line
          current_block = detect_and_start_text_block(line)
        elsif configs[current_block.table]    # optimization: only parse of the text block has a table configuration
          output current_block.parse(line)
        else                                  # otherwise output the original line
          output line
        end
      end
    end

    # Check if a line is the begining of a new text block.
    # When it is, trigger the callbacks so the text block
    # can initialize itself.
    def detect_and_start_text_block(line)
      text_blocks.detect do |block|
        matcher = block.match_start_text(line)
        if matcher && block.start_text? 
          block.on_start_text(matcher, line)
          true # result for detect
        end
      end
    end

    # Delegate method to be called by the #text_objects to get config information 
    # from a table's column
    def on_config(table:, column:, config:)
      table = (configs[table] ||= {})
      table[column] = config
    end

    # @return [String] The mutated cell or the original if there's no config for
    #                  the table/column.
    def on_cell(table:, column:, cell:)
      if config = configs[table].try(:[], column)
        Mutator.mutate(config, cell)
      else
        cell
      end
    end

    private

    # Simple wrapper to print to the configured #outputter
    def output(text)
      outputter.puts text
    end
  end
end
