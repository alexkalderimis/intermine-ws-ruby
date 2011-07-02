require 'rubygems'
require 'json'

class Model

    attr_accessor :name, :classes

    def initialize(model_data) 
        result = JSON.parse(model_data)
        @model = result["model"]
        @name = @model["name"]
        @classes = {}
        @model["classes"].each do |k, v| 
            @classes[k] = ClassDescriptor.new(v, self)
        end
        @classes.each do |name, cld| 
            cld.fields.each do |fname, fd|
                if fd.respond_to?(:referencedType)
                    refCd = self.get_class(fd.referencedType)
                    fd.referencedType = refCd
                end
            end
        end

    end

    def get_class(cls)
        if cls.is_a?(ClassDescriptor)
            return cls
        else
            return @classes[cls]
        end
    end

end

module SetHashKey 

    def set_key_value(k, v) 
        if (k == "type")
            k = "dataType"
        end
        ## create and initialize an instance variable for this 
        ## key/value pair
        self.instance_variable_set("@#{k}", v) 
        ## create the getter that returns the instance variable
        self.class.send(:define_method, k, 
            proc{self.instance_variable_get("@#{k}")})  
        ## create the setter that sets the instance variable
        self.class.send(:define_method, "#{k}=", 
            proc{|v| self.instance_variable_set("@#{k}", v)})  
    end

    def inspect
        parts = []
        self.instance_variables.each do |x|
            var = self.instance_variable_get(x)
            if var.is_a?(ClassDescriptor) || var.is_a?(Model)
                parts << x.to_s + "=" + var.to_s
            else
                parts << x.to_s + "=" + var.inspect
            end
        end
        return "<#{parts.join(' ')}>"
    end
end

class ClassDescriptor
    include SetHashKey

    attr_accessor :model, :fields

    def initialize(opts, model)
        @model = model
        @fields = {}

        field_types = {
            "attributes" => AttributeDescriptor,
            "references" => ReferenceDescriptor,
            "collections" => CollectionDescriptor
        }

        opts.each do |k,v|
            if (field_types.has_key?(k))
                v.each do |name, field| 
                    @fields[name] = field_types[k].new(field, model)
                end
            else
                set_key_value(k, v)
            end
        end
    end

    def get_field(name)
        return @fields[name]
    end

    def to_s 
        return "<#{self.class.name}:#{self.object_id} #{self.model.name}.#{@name}>"
    end

    def subclass_of(other)
        path = Path.new(other, @model)
        if @extends.include? path.end_type
            return true
        else
            @extends.each do |x|
                superCls = @model.get_class(x)
                if superCls.subclass_of(path)
                    return true
                end
            end
        end
        return false
    end
    

end

class FieldDescriptor
    include SetHashKey

    attr_accessor :model

    def initialize(opts, model) 
        @model = model
        opts.each do |k, v|
            set_key_value(k, v)
        end
    end

end

class AttributeDescriptor < FieldDescriptor
end

class ReferenceDescriptor < FieldDescriptor
end

class CollectionDescriptor < ReferenceDescriptor
end

class Path

    attr_accessor :model, :elements, :subclasses, :rootClass

    def initialize(pathstring, model=nil, subclasses={})
        @model = model
        @subclasses = subclasses
        @elements = []
        @rootClass = nil
        parse(pathstring)
    end

    def end_type
        last = @elements.last
        if last.is_a?(ClassDescriptor)
            return last.name
        elsif last.respond_to?(:referencedType)
            return last.referencedType.name
        else
            return last.dataType
        end
    end

    def length
        return @elements.length
    end

    def to_s 
        return @elements.map {|x| x.name}.join(".")
    end

    private

    def parse(pathstring)
        if pathstring.is_a?(ClassDescriptor)
            @rootClass = pathstring
            @elements << pathstring
            return
        elsif pathstring.is_a?(Path)
            @rootClass = pathstring.rootClass
            @elements = pathstring.elements
            @model = pathstring.model
            @subclasses = pathstring.subclasses
            return
        end

        bits = pathstring.split(".")
        rootName = bits.shift
        @rootClass = @model.get_class(rootName)
        if @rootClass.nil?
            raise PathException.new(pathstring, subclasses, "Invalid root class '#{rootName}'")
        end

        @elements << @rootClass
        processed = [rootName]

        current_cd = @rootClass

        while (bits.length > 0)
            this_bit = bits.shift
            fd = current_cd.get_field(this_bit)
            if fd.nil?
                subclassKey = processed.join(".")
                if @subclasses.has_key?(subclassKey)
                    subclass = model.get_class(@subclasses[subclassKey])
                    if subclass.nil?
                        raise PathException.new(pathstring, subclasses,
"'#{subclassKey}' constrained to be a '#{@subclasses[subclassKey]}', but that is not a valid class in the model")
                    end
                    current_cd = subclass
                    fd = current_cd.get_field(this_bit)
                end
                if fd.nil?
                    raise PathException.new(pathstring, subclasses,
"giving up at '#{subclassKey}.#{this_bit}'. Could not find '#{this_bit}' in '#{current_cd}'")
                end
            end
            @elements << fd
            if fd.respond_to?(:referencedType)
                current_cd = fd.referencedType
            elsif bits.length > 0
                raise PathException.new(pathstring, subclasses, 
"Attributes must be at the end of the path. Giving up at '#{this_bit}'")
            else
                current_cd = nil
            end
            processed << this_bit
        end
    end
end

class PathException < RuntimeError

    attr_reader :pathstring, :subclasses

    def initialize(pathstring=nil, subclasses={}, message=nil)
        @pathstring = pathstring
        @subclasses = subclasses
        @message = message
    end

    def to_s
        if @pathstring.nil?
            if @message.nil?
                return self.class.name
            else
                return @message
            end
        end
        preamble = "Unable to resolve '#{@pathstring}': "
        footer = " (SUBCLASSES => #{@subclasses.inspect})"
        if @message.nil?
            return preamble + footer
        else
            return preamble + @message + footer
        end
    end
end




