require 'rubygems'
require 'rest-open-uri'
require 'intermine/model'
require "intermine/query"

class Service

    VERSION_PATH = "/version"
    MODEL_PATH = "/model/json"
    QUERY_RESULTS_PATH = "/query/results"

    attr_reader :version, :root

    def initialize(root, token=nil)
        @root = root
        @token = token
        @version = fetch(@root + VERSION_PATH).to_i
        @model = nil
    end

    def model
        if @model.nil?
            data = fetch(@root + MODEL_PATH)
            @model = Model.new(data)
        end
        @model
    end

    def new_query(rootClass=nil)
        return PathQuery::Query.new(self.model, rootClass, self)
    end

    private

    def fetch(url)
        uri = URI(url)
        uri.query = "token=#{@token}" if @token
        return uri.open.read
    end
end


