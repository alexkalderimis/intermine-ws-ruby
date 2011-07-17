require File.dirname(__FILE__) + "/test_helper.rb"
require "intermine/query"
require "intermine/model"
require "intermine/lists"
require "intermine/service"

require "test/unit"


class TestQuery < Test::Unit::TestCase

    def initialize(name)
        super
        file = File.new(
            File.dirname(__FILE__) + "/data/model.json", "r")
        data = file.read
        @model = Model.new(data)
    end

    def test_instantiation
        query = PathQuery::Query.new(@model)
        assert(query.is_a?(PathQuery::Query))

        query = PathQuery::Query.new(@model, "Employee")
        assert_equal(query.root, @model.get_cd("Employee"))

        query = PathQuery::Query.new(@model, "Department.name")
        assert_equal(query.root, @model.get_cd("Department"))

        assert_raise PathException do
            PathQuery::Query.new(@model, "Foo")
        end
    end

    def test_fully_qualified_views
        views = [
            "Employee.name", 
            "Employee.age", 
            "Employee.department.name"
        ]
        expected = views.to_s


        query = PathQuery::Query.new(@model)
        query.add_views("Employee.name", "Employee.age", 
                        "Employee.department.name")
        assert_equal(query.views.to_s, expected)
            

        query = PathQuery::Query.new(@model, "Employee")
        query.add_views("Employee.name", "Employee.age", 
                        "Employee.department.name")
        assert_equal(query.views.to_s, expected)

        query = PathQuery::Query.new(@model)
        query.add_views(views)
        assert_equal(query.views.to_s, expected)

        query = PathQuery::Query.new(@model, "Employee")
        query.add_views(views)
        assert_equal(query.views.to_s, expected)
    end

    def test_bad_viewpath
        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_views("Employee.foo.id")
        end
    end

    def test_inconsistent_view_roots
        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_views("Employee.name")
            query.add_views("Department.name")
        end

    end

    def test_unqualified_views
        views = [
            "Employee.name", 
            "Employee.age", 
            "Employee.department.name"
        ]
        expected = views.to_s

        query = PathQuery::Query.new(@model, "Employee")
        query.add_views("name", "age", "department.name")
        assert_equal(query.views.to_s, expected)

        query = PathQuery::Query.new(@model, "Employee")
        query.add_views(["name", "age", "department.name"])
        assert_equal(query.views.to_s, expected)
    end

    def test_bad_unqualified_path
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise PathException do
            query.add_views("foo.id")
        end
    end

    def test_inconsistent_views_with_rooted_query
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise PathException do
            query.add_views("Department.id")
        end
    end

    def test_subclasses
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Department.employees",
            :sub_class => "Manager"
        })
        query.add_constraint({
            :path => "Department.company.departments.employees",
            :sub_class => "Manager"
        })
        expected = {
            "Department.employees" => "Manager",
            "Department.company.departments.employees" => "Manager"
        }
        assert_equal(expected, query.subclasses)
    end

    def test_problem_subclasses
        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_constraint({
                :path => "Department.employees",
                :sub_class => "Foo"
            })
        end

        query = PathQuery::Query.new(@model)
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Department.employees",
                :sub_class => "Company"
            })
        end

        query = PathQuery::Query.new(@model)
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Department.manager",
                :sub_class => "Company.departments.employees"
            })
        end

        query = PathQuery::Query.new(@model)
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Department.manager",
                :sub_class => "Employee"
            })
        end
    end

    def test_subclassed_views
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Department.employees",
            :sub_class => "Manager"
        })
        query.add_views("Department.employees.seniority")
        expected = ["Department.employees.seniority"].to_s
        assert_equal(query.views.to_s, expected)

        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_views("Department.employees.seniority")
        end
    end

    def test_joins
        query = PathQuery::Query.new(@model)
        query.add_join("Department.employees", "OUTER")
        join = query.joins.first
        assert_equal(join.path.to_s, "Department.employees")
        assert_equal(join.style, "OUTER")
        assert_equal(query.root.name, "Department")

        query = PathQuery::Query.new(@model)
        query.add_join("Department.employees")
        join = query.joins.first
        assert_equal(join.path.to_s, "Department.employees")
        assert_equal(join.style, "OUTER")

        query = PathQuery::Query.new(@model, "Department")
        query.add_join("employees")
        join = query.joins.first
        assert_equal(join.path.to_s, "Department.employees")
        assert_equal(join.style, "OUTER")

        query = PathQuery::Query.new(@model)
        query.add_join("Department.employees", "INNER")
        join = query.joins.first
        assert_equal(join.path.to_s, "Department.employees")
        assert_equal(join.style, "INNER")
    end

    def test_subclassed_joins

        query = PathQuery::Query.new(@model, "Department")

        query.add_constraint({:path => "employees", :sub_class => "CEO"})
        query.add_join("employees.secretarys")

        assert_equal(query.joins.first.path.to_s, "Department.employees.secretarys")
        assert_equal(query.joins.first.style, "OUTER")

        query = PathQuery::Query.new(@model, "Department")
        assert_raise PathException do
            query.add_join("employees.secretarys")
        end
    end

    def test_join_problems

        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_join("Foo.employees")
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise PathException do
            query.add_join("Department.employees")
        end

        query = PathQuery::Query.new(@model)
        assert_raise ArgumentError do
            query.add_join("Department.employees", "QUIRKY")
        end

        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_join("Department.employees")
            query.add_join("Company.departments")
        end
    end

    def test_unary_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee.name",
            :op => "IS NULL"
        })
        query.add_constraint({
            :path => "Employee.department",
            :op => "IS NOT NULL"
        })
        conA = query.constraints[0]
        conB = query.constraints[1]

        query = PathQuery::Query.new(@model)
        query.add_constraint(
            :path => "Employee.name",
            :op => "IS NULL"
        )
        query.add_constraint(
            :path => "Employee.department",
            :op => "IS NOT NULL"
        )
        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee.name")
        assert_equal(conB.path.to_s, "Employee.department")

        assert_equal(conA.op, "IS NULL")
        assert_equal(conB.op, "IS NOT NULL")
    end

    def test_unqualified_unary_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint(
            :path => "name",
            :op => "IS NULL"
        )

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.name")
        assert_equal(conA.op, "IS NULL")

    end

    def test_bad_unary_constraint
        query = PathQuery::Query.new(@model)
        assert_raise ArgumentError do
            query.add_constraint(
                :path => "name",
                :op => "IS MAYBE NULL"
            )
        end

        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_constraint({
                :path => "Company.foo",
                :op => "IS NULL"
            })
        end
    end

    def test_binary_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee.name",
            :op => "=",
            :value => "foo"
        })
        query.add_constraint({
            :path => "Employee.department.name",
            :op => "!=",
            :value => "foo"
        })
        query.add_constraint({
            :path => "Employee.age",
            :op => ">",
            :value => 1
        })
        query.add_constraint({
            :path => "Employee.fullTime",
            :op => "<",
            :value => false
        })
        conA = query.constraints[0]
        conB = query.constraints[1]
        conC = query.constraints[2]
        conD = query.constraints[3]

        assert_equal(conA.path.to_s, "Employee.name")
        assert_equal(conB.path.to_s, "Employee.department.name")
        assert_equal(conC.path.to_s, "Employee.age")
        assert_equal(conD.path.to_s, "Employee.fullTime")

        assert_equal(conA.op, "=")
        assert_equal(conB.op, "!=")
        assert_equal(conC.op, ">")
        assert_equal(conD.op, "<")

        assert_equal(conA.value, "foo")
        assert_equal(conB.value, "foo")
        assert_equal(conC.value, 1)
        assert_equal(conD.value, false)
    end

    def test_value_coercion
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee.age",
            :op => ">",
            :value => "1"
        })
        query.add_constraint({
            :path => "Employee.fullTime",
            :op => "<",
            :value => "false"
        })
        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee.age")
        assert_equal(conB.path.to_s, "Employee.fullTime")

        assert_equal(conA.op, ">")
        assert_equal(conB.op, "<")

        assert_equal(conA.value, 1)
        assert_equal(conB.value, false)
    end

    def test_unqualified_binary_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint({
            :path => "name",
            :op => ">=",
            :value => "foo"
        })

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.name")
        assert_equal(conA.op, ">=")
        assert_equal(conA.value, "foo")

    end

    def test_bad_binary_constraint
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "===",
                :value => "foo"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "age",
                :op => "<",
                :value => "foo"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "fullTime",
                :op => "=",
                :value => "foo"
            })
        end

        query = PathQuery::Query.new(@model)
        assert_raise PathException do
            query.add_constraint({
                :path => "Company.foo",
                :op => ">=",
                :value => "foo"
            })
        end
    end

    def test_list_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee",
            :op => "IN",
            :value => "foo"
        })
        query.add_constraint({
            :path => "Employee.department",
            :op => "NOT IN",
            :value => "foo"
        })
        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee")
        assert_equal(conB.path.to_s, "Employee.department")

        assert_equal(conA.op, "IN")
        assert_equal(conB.op, "NOT IN")

        assert_equal(conA.value, "foo")
        assert_equal(conB.value, "foo")
    end

    def test_unqualified_list_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint({
            :path => "department",
            :op => "IN",
            :value => "foo"
        })

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.department")
        assert_equal(conA.op, "IN")
        assert_equal(conA.value, "foo")
    end

    def test_bad_list_constraint
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "department.name",
                :op => "IN",
                :value => "foo"
            })
        end
    end

    def test_lookup_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee",
            :op => "LOOKUP",
            :value => "foo"
        })
        query.add_constraint({
            :path => "Employee.department",
            :op => "LOOKUP",
            :value => "foo",
            :extra_value => "bar"
        })
        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee")
        assert_equal(conB.path.to_s, "Employee.department")

        assert_equal(conA.op, "LOOKUP")
        assert_equal(conB.op, "LOOKUP")

        assert_equal(conA.value, "foo")
        assert_equal(conB.value, "foo")

        assert_equal(conA.extra_value, nil)
        assert_equal(conB.extra_value, "bar")
    end

    def test_unqualified_lookup_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint({
            :path => "department",
            :op => "LOOKUP",
            :value => "foo"
        })

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.department")
        assert_equal(conA.op, "LOOKUP")
        assert_equal(conA.value, "foo")
    end

    def test_bad_lookup_constraint
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "department.name",
                :op => "LOOKUP",
                :value => "foo"
            })
        end
    end

    def test_loop_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee",
            :op => "IS",
            :loopPath => "Employee.department.manager"
        })
        query.add_constraint({
            :path => "Employee.department",
            :op => "IS NOT",
            :loopPath => "Employee.department.company.departments"
        })
        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee")
        assert_equal(conB.path.to_s, "Employee.department")

        assert_equal(conA.op, "IS")
        assert_equal(conB.op, "IS NOT")

        assert_equal(conA.loopPath.to_s, "Employee.department.manager")
        assert_equal(conB.loopPath.to_s, "Employee.department.company.departments")

    end

    def test_unqualified_loop_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint({
            :path => "department",
            :op => "IS",
            :loopPath => "department.company.departments"
        })

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.department")
        assert_equal(conA.op, "IS")
        assert_equal(conA.loopPath.to_s, "Employee.department.company.departments")
    end

    def test_bad_lookup_constraint
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "IS",
                :loopPath => "department.manager"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Employee",
                :op => "IS",
                :loopPath => "department.manager.name"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Employee",
                :op => "IS",
                :loopPath => "department"
            })
        end
    end

    def test_multi_constraints
        query = PathQuery::Query.new(@model)
        query.add_constraint({
            :path => "Employee.name",
            :op => "ONE OF",
            :values => %w{foo bar baz}
        })

        query.add_constraint({
            :path => "Employee.age",
            :op => "NONE OF",
            :values => [1, 2, 3]
        })

        conA = query.constraints[0]
        conB = query.constraints[1]

        assert_equal(conA.path.to_s, "Employee.name")
        assert_equal(conB.path.to_s, "Employee.age")

        assert_equal(conA.op, "ONE OF")
        assert_equal(conB.op, "NONE OF")

        assert_equal(conA.values, ["foo", "bar", "baz"])
        assert_equal(conB.values, [1, 2, 3])
    end

    def test_unqualified_multi_constraint
        query = PathQuery::Query.new(@model, "Employee")
        query.add_constraint({
            :path => "department.name",
            :op => "ONE OF",
            :values => %w{Sales Marketing Janitorial}
        })

        conA = query.constraints[0]
        assert_equal(conA.path.to_s, "Employee.department.name")
        assert_equal(conA.op, "ONE OF")
        assert_equal(conA.values, %w{Sales Marketing Janitorial})
    end

    def test_bad_multi_constraint
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "ONE OF",
                :value => "foo"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Employee",
                :op => "ONE OF",
                :values => ["foo", "bar", "baz"]
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "Employee.age",
                :op => "ONE OF",
                :values => [1, 2, 3, "foo", 5]
            })
        end
    end

    def test_codes
        query = PathQuery::Query.new(@model, "Employee")
        # Check allocation of default codes
        query.add_constraint({
            :path => "name",
            :op => "=",
            :value => "foo"
        })

        # Check that subclass constraints don't get codes
        query.add_constraint({
            :path => "department.employees",
            :sub_class => "Manager"
        })

        # Check default code is next available
        query.add_constraint({
            :path => "name",
            :op => "IS NOT NULL"
        })

        # Check allocation of custom codes
        query.add_constraint({
            :path => "name",
            :op => "IS NOT NULL",
            :code => "Q"
        })

        # Check that we remember allocation of default codes
        query.add_constraint({
            :path => "name",
            :op => "IS NOT NULL",
            :code => "A"
        })

        # Check that we remember allocation of custom codes
        query.add_constraint({
            :path => "name",
            :op => "IS NOT NULL",
            :code => "Q"
        })

        codes = query.constraints.map { |x| 
            # Filter out subclass codes
            begin 
                x.code 
            rescue
                nil
            end
        }
        assert_equal(["A", nil, "B", "Q", "C", "D"], codes)
    end

    def test_code_exhaustion
        query = PathQuery::Query.new(@model, "Employee")
        # Check we can allocate all 26 default codes
        assert_nothing_raised do
            26.times do
                query.add_constraint({
                    :path => "name",
                    :op => "IS NOT NULL"
                })
            end
        end
        assert_equal(query.constraints.first.code, "A")
        assert_equal(query.constraints.last.code, "Z")

        # But 27 is too many
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise RuntimeError do
            27.times do
                query.add_constraint({
                    :path => "name",
                    :op => "IS NOT NULL"
                })
            end
        end

        # One more tips the balance, even with a custom code
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise RuntimeError do
            26.times do
                query.add_constraint({
                    :path => "name",
                    :op => "IS NOT NULL"
                })
            end
            query.add_constraint({
                :path => "name",
                :op => "IS NOT NULL",
                :code => "Z"
            })
        end
    end

    def test_illegal_codes
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "IS NOT NULL",
                :code => "a"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "IS NOT NULL",
                :code => "AA"
            })
        end

        query = PathQuery::Query.new(@model, "Employee")
        assert_raise ArgumentError do
            query.add_constraint({
                :path => "name",
                :op => "IS NOT NULL",
                :code => "Ä"
            })
        end
    end

    def test_subclassed_constraints

        query =  PathQuery::Query.new(@model, "Department")

        query.add_constraint({:path => "employees", :sub_class => "Manager"})
        query.add_constraint({:path => "employees.title", :op => "=", :value => "Ms"})

        assert_equal(query.constraints.last.path.to_s, "Department.employees.title")
        assert_equal(query.constraints.last.op, "=")
        assert_equal(query.constraints.last.value, "Ms")
        assert_equal(query.constraints.last.code, "A")

        query =  PathQuery::Query.new(@model, "Department")
        assert_raise PathException do
            query.add_constraint({:path => "employees.title", :op => "=", :value => "Ms"})
        end
    end

    def test_sort_order 

        query =  PathQuery::Query.new(@model, "Employee")

        query.add_views("name", "age", "end")

        query.add_sort_order("name", "ASC")

        assert_equal(query.sort_order.first.path, "Employee.name")
        assert_equal(query.sort_order.first.direction, "ASC")

        query.add_sort_order("age")

        assert_equal(query.sort_order.last.path, "Employee.age")
        assert_equal(query.sort_order.last.direction, "ASC")

        query.add_sort_order("end", "DESC")

        assert_equal(query.sort_order.last.path, "Employee.end")
        assert_equal(query.sort_order.last.direction, "DESC")

        assert_raise PathException do
            query.add_sort_order("foo")
        end

        assert_raise ArgumentError do
            query.add_sort_order("name", "FORWARDS")
        end

        assert_raise ArgumentError do
            query.add_sort_order("department.name")
        end

        query.add_sort_order("name", "desc")

        assert_equal(query.sort_order.last.path, "Employee.name")
        assert_equal(query.sort_order.last.direction, "DESC")
    end

    def test_subclassed_sort_order

        query = PathQuery::Query.new(@model, "Employee")

        query.add_constraint(:path => "Employee", :sub_class => "Manager")
        query.add_views(%w{name age fullTime title})
        query.add_sort_order("title")

        assert_equal(query.sort_order.first.path, "Employee.title")
        
        query = PathQuery::Query.new(@model, "Employee")
        assert_raise PathException do
            query.add_sort_order("title")
        end
    end

    def test_logic 

        query = PathQuery::Query.new(@model, "Employee")

        5.times do
            query.add_constraint(:path => "name", :op => "=", :value => "foo")
        end

        query.set_logic("A and B and C and D and E")
        assert_equal("A and B and C and D and E", query.logic.to_s)

        query.set_logic("A&B&C&D&E")
        assert_equal("A and B and C and D and E", query.logic.to_s)

        query.set_logic("A|B|C|D|E")
        assert_equal("A or B or C or D or E", query.logic.to_s)

        query.set_logic("A and B or C and D or E")
        assert_equal("A and (B or C) and (D or E)", query.logic.to_s)

        query.set_logic("A and (B or (C and (D or E)))")
        assert_equal("A and (B or (C and (D or E)))", query.logic.to_s)

        query.set_logic("(((A and B) and C) and D) and E")
        assert_equal("A and B and C and D and E", query.logic.to_s)

        query.set_logic("A and B | (C or D) and E")
        assert_equal("A and (B or C or D) and E", query.logic.to_s)

        query.set_logic("A or B or (C and D) and E")
        assert_equal("(A or B or (C and D)) and E", query.logic.to_s)

        query.set_logic("A or B or (C and D and E)")
        assert_equal("A or B or (C and D and E)", query.logic.to_s)

        assert_raise PathQuery::LogicParseError do
            query.set_logic("A B | (C or D) and E")
        end

        assert_raise PathQuery::LogicParseError do
            query.set_logic("A ( B and C)")
        end

        assert_raise PathQuery::LogicParseError do
            query.set_logic("A or B and C)")
        end

        assert_raise PathQuery::LogicParseError do
            query.set_logic("A or (B and C")
        end
    end

    def compare_xml(a, b)
        require "rexml/document"
        docA = REXML::Document.new(a.to_s)
        docB = REXML::Document.new(b.to_s)

        a_elems = docA.elements.to_a
        b_elems = docB.elements.to_a

        (0 ... a_elems.size).each do |idx|
            compare_elements(a_elems[idx], b_elems[idx])
        end
    end

    def fail_xml_compare(elemA, elemB, problem, e)
        formatter = REXML::Formatters::Pretty.new
        elemA_str = String.new
        elemB_str = String.new
        formatter.write(elemA, elemA_str)
        formatter.write(elemB, elemB_str)
        first_part = "#{elemA_str}\nis not equal to\n#{elemB_str}\n"
        
        raise Test::Unit::AssertionFailedError, "#{first_part}because #{problem} - #{e.message}" 
    end

    def compare_elements(elemA, elemB)

        begin
            assert_equal(elemA.name, elemB.name)
        rescue Test::Unit::AssertionFailedError => e
            fail_xml_compare(elemA, elemB, "names of element differ", e)
        end

        begin
            assert_equal(elemA.attributes, elemB.attributes)
        rescue Test::Unit::AssertionFailedError => e
            fail_xml_compare(elemA, elemB, "attributes of element differ", e)
        end

        begin
            assert_equal(elemA.text, elemB.text)
        rescue Test::Unit::AssertionFailedError => e
            fail_xml_compare(elemA, elemB, "text contents of element differ", e)
        end

        begin
            assert_equal(elemA.elements.size, elemB.elements.size)
        rescue Test::Unit::AssertionFailedError => e
            fail_xml_compare(elemA, elemB, "number of children of element differ", e)
        end

        a_elems = elemA.elements.to_a
        b_elems = elemB.elements.to_a

        (0 ... a_elems.size).each do |idx|
            compare_elements(a_elems[idx], b_elems[idx])
        end
    end

    def test_query_element_xml

        query =  PathQuery::Query.new(@model, "Employee")
        query.add_views("name", "age", "fullTime", "department.name")
        
        expected = "<query model='testmodel' view='Employee.name Employee.age Employee.fullTime Employee.department.name' sortOrder='Employee.name ASC'/>"

        compare_xml(expected, query.to_xml)

        query.title = "Ruby Query"
        query.add_sort_order("age", "desc")

        expected = "<query model='testmodel' title='Ruby Query' view='Employee.name Employee.age Employee.fullTime Employee.department.name' sortOrder='Employee.age DESC'/>"
        compare_xml(expected, query.to_xml)

        query.add_sort_order("name")
        expected = "<query model='testmodel' title='Ruby Query' view='Employee.name Employee.age Employee.fullTime Employee.department.name' sortOrder='Employee.age DESC Employee.name ASC'/>"
        compare_xml(expected, query.to_xml)

    end

    def test_constraint_xml
        query =  PathQuery::Query.new(@model, "Employee")
        query.add_views("name", "age", "fullTime", "department.name")

        query.add_constraint({:path => "department", :op => "IS NOT NULL"})
        query.add_constraint({
            :path => "name", 
            :op => "<", 
            :value => "foo"
        })
        query.add_constraint({
            :path => "age",
            :op => "ONE OF",
            :values => [17, 23, 37]
        })
        query.add_constraint({
            :path => "Employee",
            :op => "IN",
            :value => "bar"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "IS",
            :loopPath => "department.manager"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "LOOKUP",
            :value => "quux"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "LOOKUP",
            :value => "zop",
            :extra_value => "zip"
        })
        query.add_constraint({
            :path => "Employee",
            :sub_class => "Manager"
        })
        query.add_views("title")

        expected = "<query model='testmodel' view='Employee.name Employee.age Employee.fullTime Employee.department.name Employee.title' sortOrder='Employee.name ASC'>" + 
        "<constraint type='Manager' path='Employee'/>" + 
        "<constraint op='IS NOT NULL' code='A' path='Employee.department'/>" + 
        "<constraint op='&lt;' code='B' value='foo' path='Employee.name'/>" + 
        "<constraint op='ONE OF' code='C' path='Employee.age'>" + 
            "<value>17</value><value>23</value><value>37</value>" +
        "</constraint>" + 
        "<constraint op='IN' code='D' value='bar' path='Employee'/>" + 
        "<constraint loopPath='Employee.department.manager' op='=' code='E' path='Employee'/>" +
        "<constraint op='LOOKUP' code='F' value='quux' path='Employee'/>" + 
        "<constraint extraValue='zip' op='LOOKUP' code='G' value='zop' path='Employee'/>" + 
        "</query>"

        compare_xml(expected, query.to_xml.to_s)
    end

    def test_join_xml

        query =  PathQuery::Query.new(@model, "Employee")
        query.add_views("name", "age", "fullTime", "department.name")

        query.add_join("department")
        query.add_join("department.company", "INNER")
        query.add_join("department.company.address", "OUTER")

        expected = "<query model='testmodel' view='Employee.name Employee.age Employee.fullTime Employee.department.name' sortOrder='Employee.name ASC'>" + 
            "<join path='Employee.department' style='OUTER'/>" +
            "<join path='Employee.department.company' style='INNER'/>" +
            "<join path='Employee.department.company.address' style='OUTER'/>" +
            "</query>"

        compare_xml(expected, query.to_xml)
    end

    def test_all_xml
        query =  PathQuery::Query.new(@model, "Employee")
        query.add_views("name", "age", "fullTime", "department.name")
        query.add_constraint({
            :path => "Employee",
            :sub_class => "Manager"
        })
        query.add_views("title")
        query.add_sort_order("title", "desc")

        query.add_join("department")
        query.add_join("department.company", "INNER")
        query.add_join("department.company.address", "OUTER")

        query.add_constraint({:path => "department", :op => "IS NOT NULL"})
        query.add_constraint({
            :path => "name", 
            :op => "<", 
            :value => "foo"
        })
        query.add_constraint({
            :path => "age",
            :op => "ONE OF",
            :values => [17, 23, 37]
        })
        query.add_constraint({
            :path => "Employee",
            :op => "IN",
            :value => "bar"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "IS",
            :loopPath => "department.manager"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "LOOKUP",
            :value => "quux"
        })
        query.add_constraint({
            :path => "Employee",
            :op => "LOOKUP",
            :value => "zop",
            :extra_value => "zip"
        })

        expected = "<query model='testmodel' view='Employee.name Employee.age Employee.fullTime Employee.department.name Employee.title' sortOrder='Employee.title DESC'>" + 
            "<join path='Employee.department' style='OUTER'/>" +
            "<join path='Employee.department.company' style='INNER'/>" +
            "<join path='Employee.department.company.address' style='OUTER'/>" +
            "<constraint type='Manager' path='Employee'/>" + 
            "<constraint op='IS NOT NULL' code='A' path='Employee.department'/>" + 
            "<constraint op='&lt;' code='B' value='foo' path='Employee.name'/>" + 
            "<constraint op='ONE OF' code='C' path='Employee.age'>" + 
                "<value>17</value><value>23</value><value>37</value>" +
            "</constraint>" + 
            "<constraint op='IN' code='D' value='bar' path='Employee'/>" + 
            "<constraint loopPath='Employee.department.manager' op='=' code='E' path='Employee'/>" +
            "<constraint op='LOOKUP' code='F' value='quux' path='Employee'/>" + 
            "<constraint extraValue='zip' op='LOOKUP' code='G' value='zop' path='Employee'/>" + 
        "</query>"

        compare_xml(expected, query.to_xml)

    end

    def test_unmarshall
        # Tricky xml with all constraint types and subclassing, as well as integer values
        xml = "<query model='testmodel' view='Employee.name Employee.age Employee.fullTime Employee.department.name Employee.title' sortOrder='Employee.title DESC'>" + 
            "<join path='Employee.department' style='OUTER'/>" +
            "<join path='Employee.department.company' style='INNER'/>" +
            "<join path='Employee.department.company.address' style='OUTER'/>" +
            "<constraint type='Manager' path='Employee'/>" + 
            "<constraint op='IS NOT NULL' code='A' path='Employee.department'/>" + 
            "<constraint op='&lt;' code='B' value='foo' path='Employee.name'/>" + 
            "<constraint op='ONE OF' code='C' path='Employee.age'>" + 
                "<value>17</value><value>23</value><value>37</value>" +
            "</constraint>" + 
            "<constraint op='IN' code='D' value='bar' path='Employee'/>" + 
            "<constraint loopPath='Employee.department.manager' op='=' code='E' path='Employee'/>" +
            "<constraint op='LOOKUP' code='F' value='quux' path='Employee'/>" + 
            "<constraint extraValue='zip' op='LOOKUP' code='G' value='zop' path='Employee'/>" + 
        "</query>"

        q = PathQuery::Query.parser(@model).parse(xml)

        compare_xml(xml, q.to_xml)
    end

end
