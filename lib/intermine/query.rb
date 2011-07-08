require "rexml/document"
require "intermine/model"

module PathQuery

    include REXML
    class Query
        attr_accessor :name, :title, :root
        attr_reader :model, :joins, :constraints, :views, :sort_order, :logic

        def initialize(model, root=nil)
            @model = model
            if root
                @root = Path.new(root, model).rootClass
            end
            @constraints = []
            @joins = []
            @views = []
            @sort_order = []
            @used_codes = []
            @logic_parser = LogicParser.new(self)
        end

        def to_xml
            doc = REXML::Document.new

            if @sort_order.empty?
                so = SortOrder.new(@views.first, "ASC")
            else
                so = @sort_order
            end

            query = doc.add_element("query", {
                "name" => @name, 
                "model" => @model.name, 
                "title" => @title, 
                "sortOrder" => so,
                "view" => @views.join(" ")
            }.delete_if { |k, v | !v })
            @joins.each { |join| 
                query.add_element("join", join.attrs) 
            }
            @constraints.select {|x| x.is_a?(SubClassConstraint)}.each { |con|
                query.add_element(con.to_elem) 
            }
            @constraints.select {|x| !x.is_a?(SubClassConstraint)}.each { |con|
                query.add_element(con.to_elem) 
            }
            return doc
        end

        def add_prefix(x)
            if @root && !x.start_with?(@root.name)
                return @root.name + "." + x
            else 
                return x
            end
        end
        
        def get_constraint(code)
            @constraints.each do |x|
                if x.code == code
                    return x
                end
            end
            raise ArgumentError, "#{code} not in query"
        end

        def add_views(*views)
            views.flatten.map do |x| 
                y = add_prefix(x)
                path = Path.new(y, @model, subclasses)
                if @root.nil?
                    @root = path.rootClass
                end
                @views << path
            end
        end

        def subclasses
            subclasses = {}
            @constraints.each do |con|
                if con.is_a?(SubClassConstraint)
                    subclasses[con.path.to_s] = con.sub_class.to_s
                end
            end
            return subclasses
        end

        def add_join(path, style="OUTER")
            p = Path.new(add_prefix(path), @model, subclasses)
            if @root.nil?
                @root = p.rootClass
            end
            @joins << Join.new(p, style)
        end

        def add_sort_order(path, direction="ASC") 
            p = Path.new(add_prefix(path), @model, subclasses)
            if !@views.include? p
                raise ArgumentError, "Sort order (#{p}) not in view"
            end
            @sort_order << SortOrder.new(p, direction)
        end

        def add_constraint(parameters)
            classes = [SingleValueConstraint, SubClassConstraint, 
                LookupConstraint, MultiValueConstraint, 
                UnaryConstraint, LoopConstraint, ListConstraint]
            attr_keys = parameters.keys
            suitable_classes = classes.select { |cls| 
                is_suitable = true
                attr_keys.each { |key| 
                    is_suitable = is_suitable && (cls.method_defined?(key)) 
                    if key.to_s == "op"
                        is_suitable = is_suitable && cls.valid_ops.include?(parameters[key])
                    end
                }
                is_suitable
            }
            if suitable_classes.size > 1
                raise ArgumentError, "More than one class found for #{parameters}"
            elsif suitable_classes.size < 1
                raise ArgumentError, "No suitable classes found for #{parameters}"
            end

            cls = suitable_classes.first
            con = cls.new
            parameters.each_pair { |key, value|
                if key == :path || key == :loopPath
                    value = Path.new(add_prefix(value), @model, subclasses)
                end
                if key == :sub_class
                    value = Path.new(value, @model)
                end
                con.send(key.to_s + '=', value)
            }
            con.validate
            if con.respond_to?(:code)
                code = con.code
                if code.nil?
                    con.code = next_code
                else
                    code = code.to_s
                    if !is_valid_codestr(code)
                        raise ArgumentError, "Coded must be between A and Z, got: #{code}"
                    end
                    if @used_codes.include?(code[0])
                        con.code = next_code
                    else
                        @used_codes << code[0]
                    end
                end
            end

            @constraints << con
        end

        def set_logic(value)
            if value.is_a?(LogicGroup)
                @logic = value
            else
                @logic = @logic_parser.parse_logic(value)
            end
        end

        private 

        def lowest_code 
            return "A"[0]
        end

        def highest_code
            return "Z"[0]
        end

        def is_valid_codestr(str)
            return (str.length == 1) && is_valid_code(str[0])
        end

        def is_valid_code(chr)
            return ((chr >= lowest_code) && (chr <= highest_code))
        end

        def next_code
            c = lowest_code
            while is_valid_code(c)
                if !@used_codes.include?(c)
                    @used_codes << c
                    return c.chr
                end
                c += 1
            end
            raise RuntimeError, "Maximum number of codes reached - all 26 have been allocated"
        end

    end

    module PathFeature
        attr_accessor :path

        def validate
        end
    end

    module Coded
        attr_accessor :code, :op
        def self.included(base)
            base.extend(ClassMethods)
        end

        module ClassMethods
            def valid_ops
                return @valid_ops
            end
        end

        def to_elem
            attributes = {
                "path" => @path,
                "op" => @op,
                "code" => @code
            }.delete_if {|k,v| !v}
            elem = REXML::Element.new("constraint")
            elem.add_attributes(attributes)
            return elem
        end
    end

    class SubClassConstraint
        include PathFeature
        attr_accessor :sub_class

        def to_elem
            attributes = {
                "path" => @path,
                "type" => @sub_class
            }
            elem = REXML::Element.new("constraint")
            elem.add_attributes(attributes)
            return elem
        end

        def validate 
            if @path.elements.last.is_a?(AttributeDescriptor)
                raise ArgumentError, "#{self.class.name}s must be on objects or references to objects"
            end
            if @sub_class.length > 1
                raise ArgumentError, "#{self.class.name} expects sub-classes to be named as bare class names"
            end
            model = @path.model
            cdA = model.get_cd(@path.end_type)
            cdB = model.get_cd(@sub_class.end_type)
            if !cdB.subclass_of(cdA)
                raise ArgumentError, "The subclass in a #{self.class.name} must be a subclass of its path, but #{cdB} is not a subclass of #{cdA}"
            end

        end

    end

    module ObjectConstraint
        def validate
            if @path.elements.last.is_a?(AttributeDescriptor)
                raise ArgumentError, "#{self.class.name}s must be on objects or references to objects"
            end
        end
    end

    module AttributeConstraint
        def validate
            if !@path.elements.last.is_a?(AttributeDescriptor)
                raise ArgumentError, "Attribute constraints must be on attributes"
            end
        end

        def validate_value(val)
            nums = ["Float", "Double", "float", "double"]
            ints = ["Integer", "int"]
            bools = ["Boolean", "boolean"]
            dataType = @path.elements.last.dataType.split(".").last
            if nums.include?(dataType)
                if !val.is_a?(Numeric)
                    raise ArgumentError, "value #{val} is not numeric for #{@path}"
                end
            end
            if ints.include?(dataType)
                if !val.is_a?(Integer)
                    raise ArgumentError, "value #{val} is not an integer for #{@path}"
                end
            end
            if bools.include?(dataType)
                if !val.is_a?(TrueClass) && !val.is_a?(FalseClass)
                    raise ArgumentError, "value #{val} is not a boolean value for #{@path}"
                end
            end
        end
    end

    class SingleValueConstraint
        @valid_ops = ["=", ">", "<", ">=", "<=", "!="]
        include PathFeature
        include Coded
        include AttributeConstraint
        attr_accessor :value

        def to_elem
            elem = super
            attributes = {"value" => @value}
            elem.add_attributes(attributes)
            return elem
        end

        def validate 
            super
            validate_value(@value)
        end

    end


    class ListConstraint < SingleValueConstraint
        @valid_ops = ["IN", "NOT IN"]
        include ObjectConstraint
    end

    class LoopConstraint
        include PathFeature
        include Coded
        attr_accessor :loopPath
        @valid_ops = ["IS", "IS NOT"]

        def LoopConstraint.xml_ops
            return { "IS" => "=", "IS NOT" => "!=" }
        end

        def to_elem
            elem = super
            elem.add_attribute("op", LoopConstraint.xml_ops[@op])
            elem.add_attribute("loopPath", @loopPath)
            return elem
        end

        def validate
            if @path.elements.last.is_a?(AttributeDescriptor)
                raise ArgumentError, "#{self.class.name}s must be on objects or references to objects"
            end
            if @loopPath.elements.last.is_a?(AttributeDescriptor)
                raise ArgumentError, "loopPaths on #{self.class.name}s must be on objects or references to objects"
            end
            model = @path.model
            cdA = model.get_cd(@path.end_type)
            cdB = model.get_cd(@loopPath.end_type)
            if !(cdA == cdB) && !cdA.subclass_of(cdB) && !cdB.subclass_of(cdA)
                raise ArgumentError, "Incompatible types in #{self.class.name}: #{@path} -> #{cdA} and #{@loopPath} -> #{cdB}"
            end
        end

    end

    class UnaryConstraint
        include PathFeature
        include Coded
        @valid_ops = ["IS NULL", "IS NOT NULL"]

    end

    class LookupConstraint < ListConstraint
        @valid_ops = ["LOOKUP"]
        attr_accessor :extra_value

        def to_elem
            elem = super
            if @extra_value
                elem.add_attribute("extraValue", @extra_value)
            end
            return elem
        end

    end

    class MultiValueConstraint 
        include PathFeature
        include Coded
        include AttributeConstraint
        @valid_ops = ["ONE OF", "NONE OF"]

        attr_accessor :values
        def to_elem 
            elem = super
            @values.each { |x|
                value = REXML::Element.new("value")
                value.add_text(x.to_s)
                elem.add_element(value)
            }
            return elem
        end

        def validate
            super
            @values.each do |val|
                validate_value(val)
            end
        end
    end

    class SortOrder 
        include PathFeature
        attr_accessor :direction
        class << self;  attr_accessor :valid_directions end
        @valid_directions = %w{ASC DESC}

        def initialize(path, direction) 
            direction.upcase!
            unless SortOrder.valid_directions.include? direction
                raise ArgumentError, "Illegal sort direction: #{direction}"
            end
            self.path = path
            self.direction = direction
        end

        def to_s
            return @path.to_s + " " + @direction
        end
    end

    class Join 
        include PathFeature
        attr_accessor :style
        class << self;  attr_accessor :valid_styles end
        @valid_styles = %{INNER OUTER}

        def initialize(path, style)
            unless Join.valid_styles.include?(style)
                raise ArgumentError, "Invalid style: #{style}"
            end
            self.path = path
            self.style = style
        end

        def attrs
            attributes = {
                "path" => @path, 
                "style" => @style
            }
            return attributes
        end
    end

    class LogicNode
    end

    class LogicGroup < LogicNode

        attr_reader :left, :right, :op
        attr_accessor :parent

        def initialize(left, op, right, parent=nil)
            if !["AND", "OR"].include?(op)
                raise ArgumentError, "#{op} is not a legal logical operator"
            end
            @parent = parent
            @left = left
            @op = op
            @right = right
            [left, right].each do |node|
                if node.is_a?(LogicGroup)
                    node.parent = self
                end
            end
        end

        def to_s
            core = [@left.code, @op.downcase, @right.code].join(" ")
            if @parent && @op != @parent.op
                return "(#{core})"
            else
                return core
            end
        end

        def code
            return to_s
        end

    end

    class LogicParseError < ArgumentError
    end

    class LogicParser

        class << self;  attr_accessor :precedence, :ops end
        @precedence = {
            "AND" => 2,
            "OR"  => 1,
            "("   => 3, 
            ")"   => 3
        }

        @ops = {
            "AND" => "AND",
            "&"   => "AND",
            "&&"  => "AND",
            "OR"  => "OR",
            "|"   => "OR",
            "||"  => "OR",
            "("   => "(",
            ")"   => ")"
        }

        def initialize(query)
            @query = query
        end

        def parse_logic(str)
            tokens = str.upcase.split(/(?:\s+|\b)/).map do |x| 
                LogicParser.ops.fetch(x, x.split(//))
            end
            tokens.flatten!

            check_syntax(tokens)
            postfix_tokens = infix_to_postfix(tokens)
            ast = postfix_to_tree(postfix_tokens)
            return ast
        end

        private

        def infix_to_postfix(tokens)
            stack = []
            postfix_tokens = []
            tokens.each do |x|
                if !LogicParser.ops.include?(x)
                    postfix_tokens << x
                else
                    case x
                    when "("
                        stack << x
                    when ")"
                        while !stack.empty?
                            last_op = stack.pop
                            if last_op == "("
                                if !stack.empty?
                                    previous_op = stack.pop
                                    if previous_op != "("
                                        postfix_tokens << previous_op
                                        break
                                    end
                                end
                            else 
                                postfix_tokens << last_op
                            end
                        end
                    else
                        while !stack.empty? and LogicParser.precedence[stack.last] <= LogicParser.precedence[x]
                            prev_op = stack.pop
                            if prev_op != "("
                                postfix_tokens << prev_op
                            end
                        end
                        stack << x
                    end
                end
            end
            while !stack.empty?
                postfix_tokens << stack.pop
            end
            return postfix_tokens
        end

        def check_syntax(tokens)
            need_op = false
            need_bin_op_or_bracket = false
            processed = []
            open_brackets = 0
            tokens.each do |x|
                if !LogicParser.ops.include?(x)
                    if need_op
                        raise LogicParseError, "Expected an operator after '#{processed.join(' ')}', but got #{x}"
                    elsif need_bin_op_or_bracket
                        raise LogicParseError, "Logic grouping error after '#{processed.join(' ')}', expected an operator or closing bracket, but got #{x}"
                    end
                    need_op = true
                else
                    need_op = false
                    case x
                    when "("
                        if !processed.empty? && !LogicParser.ops.include?(processed.last)
                            raise LogicParseError, "Logic grouping error after '#{processed.join(' ')}', got #{x}"
                        elsif need_bin_op_or_bracket
                            raise LogicParseError, "Logic grouping error after '#{processed.join(' ')}', got #{x}"
                        end
                        open_brackets += 1
                    when ")"
                        need_bin_op_or_bracket = true
                        open_brackets -= 1
                    else
                        need_bin_op_or_bracket = false
                    end
                end
                processed << x
            end
            if open_brackets < 0
                raise LogicParseError, "Unmatched closing bracket in #{tokens.join(' ')}"
            elsif open_brackets > 0
                raise LogicParseError, "Unmatched opening bracket in #{tokens.join(' ')}"
            end
        end

        def postfix_to_tree(tokens)
            stack = []
            tokens.each do |x|
                if !LogicParser.ops.include?(x)
                    stack << x
                else
                    right = stack.pop
                    left = stack.pop
                    right = (right.is_a?(LogicGroup)) ? right : @query.get_constraint(right)
                    left = (left.is_a?(LogicGroup)) ? left : @query.get_constraint(left)
                    stack << LogicGroup.new(left, x, right)
                end
            end
            if stack.size != 1
                raise LogicParseError, "Tree does not have a unique root"
            end
            return stack.pop
        end

        def precedence_of(op)
            return LogicParser.precedence[op]
        end

    end
end
