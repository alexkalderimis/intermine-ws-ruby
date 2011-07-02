require "rexml/document"

module PathQuery

    include REXML
    class Query
        attr_accessor :name, :model, :title, :sort_order, :views

        def to_xml
            doc = REXML::Document.new
            query = doc.add_element("query", {"name" => @name, "model" => @model, "title" => @title, "sort_order" => @sort_order, "view" => @views.join(" ")})
            @joins.each { |join| query.add_element("join", join.attrs) }
            @constraints.each { |con| query.add_element(con.to_elem) }
            return doc
        end

        def initialize(root=nil)
            @root = root
            @constraints = []
            @joins = []
            @views = []
        end

        def add_views(*views)
            @views << views.map { |x| x.start_with?(@root) ? x : @root + "." + x }
        end

        def add_join(path, style="OUTER")
            @joins << Join.new(path, style)
        end

        def add_constraint(parameters)
            classes = [AttributeConstraint, SubClassConstraint, LookupConstraint, MultiValueConstraint, UnaryConstraint, LoopConstraint, ListConstraint]
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
                raise "More than one class found for #{parameters}"
            elsif suitable_classes.size < 1
                raise "No suitable classes found for #{parameters}"
            end

            cls = suitable_classes.first
            con = cls.new
            parameters.each_pair { |key, value|
                if key == :path
                    value = value.start_with?(@root) ? value : @root + "." + value
                end
                con.send(key.to_s + '=', value)
            }

            @constraints << con
        end

    end

    module PathFeature
        attr_accessor :path
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
    end

    class AttributeConstraint
        @valid_ops = ["=", ">", "<", ">=", "<=", "!="]
        include PathFeature
        include Coded
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
    end

    class ListConstraint < AttributeConstraint
        @valid_ops = ["IN", "NOT IN"]
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

    class LookupConstraint < AttributeConstraint
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
        @valid_ops = ["ONE OF", "ONE OF"]

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
    end

    class Join 
        include PathFeature
        attr_accessor :style
        class << self;  attr_accessor :valid_styles end
        @valid_styles = %{INNER OUTER}

        def initialize(path, style)
            unless Join.valid_styles.include?(style)
                raise "Invalid style: #{style}"
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
