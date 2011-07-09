require 'rubygems'
require "json"

module Results

    class ResultsRow

        def initialize(results, columns)
            @results = results.is_a?(Array) ? results : JSON.parse(results)
            unless @results.is_a?(Array)
                raise ArgumentError, "Bad results format: #{results}"
            end
            unless @results.size == columns.size
                raise ArgumentError, "Column size (#{columns.size}) != results size (#{@results.size})"
            end

            @columns = columns
        end

        def [](key)
            if key.is_a?(Integer)
                idx = key
            else
                idx = index_for(key)
            end
            if idx.nil?
                raise IndexError, "Bad key: #{key}"
            end
            begin
                result = @results[idx]["value"]
            rescue NoMethodError
                raise IndexError, "Bad key: #{key}"
            end
            return result
        end

        def to_a
            return @results.map {|x| x["value"]}
        end

        def to_h
            hash = {}
            @results.each_index do |x|
                key = @columns[x]
                hash[key] = self[key]
            end
            return hash
        end

        private

        def index_for(key)
            if @indexes.nil?
                @indexes = {}
                @results.each_index do |idx|
                    idx_key = @columns[idx]
                    @indexes[idx_key] = idx
                end
            end
            return @indexes[key]
        end
    end

end
