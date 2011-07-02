require "test_helper"
require "intermine/model"

require "test/unit"

class TestModel < Test::Unit::TestCase

    def initialize(name)
        super
        file = File.new("data/model.json", "r")
        data = file.read
        @model = Model.new(data)
    end

    def test_parse
        assert_equal(@model.classes.size, 19)

        dept = @model.get_class("Department")
        assert_equal("Department", dept.name)
        assert_equal(false, dept.isInterface)
        assert_equal(6, dept.fields.size)
        assert_equal(dept.fields.keys, ["company", "name", "manager", "id", "rejectedEmployee", "employees"])

        assert_equal(dept.get_field("company").referencedType, @model.get_class("Company"))

        manager = @model.get_class("Manager")
        assert(manager.subclass_of(@model.get_class("Employee")))
        assert(manager.subclass_of("Employee"))
        assert(manager.subclass_of("HasAddress"))
        assert(!manager.subclass_of("Company"))
        assert(manager.subclass_of("Company.departments.employees"))
        assert(!manager.subclass_of("Company.name"))
        assert_raise(PathException) {manager.subclass_of("Foo")}
    end

    def test_good_paths

        path = Path.new("Employee.name", @model)
        assert_equal(2, path.length)
        assert_equal("java.lang.String", path.end_type)

        path = Path.new("Employee.department.company.departments", @model)
        assert_equal(4, path.length)
        assert_equal("Department", path.end_type)

        path = Path.new("Employee.department.company.departments.employees.address.address", @model)
        assert_equal(7, path.length)
        assert_equal("java.lang.String", path.end_type)

        path = Path.new("Department.employees.seniority", @model, {"Department.employees" => "Manager"})
        assert_equal(3, path.length)
        assert_equal("java.lang.Integer", path.end_type)

        path = Path.new("Department.employees.id", @model)
        assert_equal(3, path.length)
        assert_equal("java.lang.Integer", path.end_type)

    end

    def test_bad_paths

        assert_raise(PathException) do
            Path.new("Foo.bar", @model)
        end

        assert_raise(PathException) do
            Path.new("Department.employees.foo", @model, {"Department.employees" => "Manager"})
        end

        assert_raise(PathException) do
            Path.new("Department.employees.seniority", @model, {"Department.employees" => "Foo"})
        end

        assert_raise(PathException) do
            Path.new("Employee.department.name.departments", @model)
        end

    end

end
