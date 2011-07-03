require "rexml/document"
require "intermine/model"

module PathQuery

    include REXML
    class Query
        attr_accessor :name, :title, :sort_order, :root
        attr_reader :model, :joins, :constraints, :views

        def initialize(model, root=nil)
            @model = model
            if root
                @root = Path.new(root, model).rootClass
            end
            @constraints = []
            @joins = []
            @views = []
            @used_codes = []
        end

        def to_xml
            doc = REXML::Document.new
            query = doc.add_element("query", {
                "name" => @name, 
                "model" => @model.name, 
                "title" => @title, 
                "sort_order" => @sort_order, 
                "view" => @views.join(" ")
            })
            @joins.each { |join| 
                query.add_element("join", join.attrs) 
            }
            @constraints.each { |con| 
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
            cdA = model.get_class(@path.end_type)
            cdB = model.get_class(@sub_class.end_type)
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
            attributes = {
                "path" => @path,
                "op" => @op,
                "value" => @value
            }
            elem = REXML::Element.new("constraint")
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
            attributes = {
                "path" => @path,
                "op" => LoopConstraint.xml_ops[@op],
                "loopPath" => @loopPath
            }
            elem = REXML::Element.new("constraint")
            elem.add_attributes(attributes)
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
            cdA = model.get_class(@path.end_type)
            cdB = model.get_class(@loopPath.end_type)
            if !(cdA == cdB) && !cdA.subclass_of(cdB) && !cdB.subclass_of(cdA)
                raise ArgumentError, "Incompatible types in #{self.class.name}: #{@path} -> #{cdA} and #{@loopPath} -> #{cdB}"
            end
        end

    end

    class UnaryConstraint
        include PathFeature
        include Coded
        @valid_ops = ["IS NULL", "IS NOT NULL"]

        def to_elem
            attributes = {
                "path" => @path,
                "op" => @op,
            }
            elem = REXML::Element.new("constraint")
            elem.add_attributes(attributes)
            return elem
        end
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
            elem = REXML::Element.new("constraint")
            elem.add_attributes({"path" => @path, "op" => @op})
            @values.each { |x|
                value = REXML::Element.new("value")
                value.add_text(x)
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
end
