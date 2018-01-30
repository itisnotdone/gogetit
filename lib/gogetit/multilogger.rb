require 'logger'

module Gogetit
  # It was just taken from below source. Thanks to clowder!
  # https://gist.github.com/clowder/3639600
  class MultiLogger
    attr_reader :level

    def initialize(args={})
      @level = args[:level] || Logger::Severity::INFO
      @loggers = []

      Array(args[:loggers]).each { |logger| add_logger(logger) }
    end

    def add_logger(logger)
      logger.level = level
      @loggers << logger
    end

    def level=(level)
      @level = level
      @loggers.each { |logger| logger.level = level }
    end

    def datetime_format=(format)
      @loggers.each { |logger| logger.datetime_format = format }
    end

    def formatter=(format)
      @loggers.each { |logger| logger.formatter = format }
    end

    def progname=(name)
      @loggers.each { |logger| logger.progname = name }
    end

    def close
      @loggers.map(&:close)
    end

    def add(level, *args)
      @loggers.each { |logger| logger.add(level, args) }
    end

    Logger::Severity.constants.each do |level|
      define_method(level.downcase) do |*args|
        if level == :ERROR
          @loggers.each { |logger| logger.send(level.downcase, "\e[31m#{args}\e[0m") }
        else
          @loggers.each { |logger| logger.send(level.downcase, "\e[36m#{args}\e[0m") }
        end
      end

      define_method("#{ level.downcase }?".to_sym) do
        @level <= Logger::Severity.const_get(level)
      end
    end
  end
end
