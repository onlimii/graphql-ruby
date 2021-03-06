require 'spec_helper'

describe GraphQL::Query do
  let(:query_string) { %|
    query getFlavor($cheeseId: Int!) {
      brie: cheese(id: 1)   { ...cheeseFields, taste: flavor },
      cheese(id: $cheeseId)  {
        __typename,
        id,
        ...cheeseFields,
        ... edibleFields,
        ... on Cheese { cheeseKind: flavor },
      }
      fromSource(source: COW) { id }
      fromSheep: fromSource(source: SHEEP) { id }
      firstSheep: searchDairy(product: {source: SHEEP}) {
        __typename,
        ... dairyFields,
        ... milkFields
      }
      favoriteEdible { __typename, fatContent }
    }
    fragment cheeseFields on Cheese { flavor }
    fragment edibleFields on Edible { fatContent }
    fragment milkFields on Milk { source }
    fragment dairyFields on AnimalProduct {
       ... on Cheese { flavor }
       ... on Milk   { source }
    }
  |}
  let(:debug) { false }
  let(:operation_name) { nil }
  let(:query_variables) { {"cheeseId" => 2} }
  let(:query) { GraphQL::Query.new(
    DummySchema,
    query_string,
    variables: query_variables,
    debug: debug,
    operation_name: operation_name,
  )}
  let(:result) { query.result }
  describe '#result' do
    it 'returns fields on objects' do
      expected = {"data"=> {
          "brie" =>   { "flavor" => "Brie", "taste" => "Brie" },
          "cheese" => {
            "__typename" => "Cheese",
            "id" => 2,
            "flavor" => "Gouda",
            "fatContent" => 0.3,
            "cheeseKind" => "Gouda",
          },
          "fromSource" => [{ "id" => 1 }, {"id" => 2}],
          "fromSheep"=>[{"id"=>3}],
          "firstSheep" => { "__typename" => "Cheese", "flavor" => "Manchego" },
          "favoriteEdible"=>{"__typename"=>"Milk", "fatContent"=>0.04},
      }}
      assert_equal(expected, result)
    end

    describe "when it hits null objects" do
      let(:query_string) {%|
        {
          maybeNull {
            cheese {
              flavor,
              similarCheese(source: [SHEEP]) { flavor }
            }
          }
        }
      |}

      it "skips null objects" do
        expected = {"data"=> {
          "maybeNull" => { "cheese" => nil }
        }}
        assert_equal(expected, result)
      end
    end
  end

  it 'exposes fragments' do
    assert_equal(GraphQL::Language::Nodes::FragmentDefinition, query.fragments['cheeseFields'].class)
  end

  it 'correctly identifies parse error location' do
    # "Correct" is a bit of an overstatement. All Parslet errors get surfaced
    # at the beginning of the query they were in, since Parslet sees the query
    # as invalid. It would be great to have more granularity here.
    e = assert_raises(GraphQL::ParseError) do
      GraphQL.parse("
        query getCoupons {
          allCoupons: {data{id}}
        }
      ")
    end
    assert_equal('Extra input after last repetition at line 2 char 9.', e.message)
    assert_equal(2, e.line)
    assert_equal(9, e.col)
  end

  describe "merging fragments with different keys" do
    let(:query_string) { %|
      query getCheeseFieldsThroughDairy {
        dairy {
          ...flavorFragment
          ...fatContentFragment
        }
      }
      fragment flavorFragment on Dairy {
        cheese {
          flavor
        }
        milks {
          id
        }
      }
      fragment fatContentFragment on Dairy {
        cheese {
          fatContent
        }
        milks {
          fatContent
        }
      }
    |}

    it "should include keys from each fragment" do
      expected = {"data" => {
        "dairy" => {
          "cheese" => {
            "flavor" => "Brie",
            "fatContent" => 0.19
          },
          "milks" => [
            {
              "id" => "1",
              "fatContent" => 0.04,
            }
          ],
        }
      }}
      assert_equal(expected, result)
    end
  end

  describe "malformed queries" do
    describe "whitespace-only" do
      let(:query_string) { " " }
      it "doesn't blow up" do
        assert_equal({}, result)
      end
    end

    describe "empty string" do
      let(:query_string) { "" }
      it "doesn't blow up" do
        assert_equal({}, result)
      end
    end
  end

  describe 'context' do
    let(:query_type) { GraphQL::ObjectType.define {
      field :context, types.String do
        argument :key, !types.String
        resolve -> (target, args, ctx) { ctx[args[:key]] }
      end
      field :contextAstNodeName, types.String do
        resolve -> (target, args, ctx) { ctx.ast_node.class.name }
      end
    }}
    let(:schema) { GraphQL::Schema.new(query: query_type, mutation: nil)}
    let(:query) { GraphQL::Query.new(schema, query_string, context: {"some_key" => "some value"})}

    describe "access to passed-in values" do
      let(:query_string) { %|
        query getCtx { context(key: "some_key") }
      |}

      it 'passes context to fields' do
        expected = {"data" => {"context" => "some value"}}
        assert_equal(expected, query.result)
      end
    end

    describe "access to the AST node" do
      let(:query_string) { %|
        query getCtx { contextAstNodeName }
      |}

      it 'provides access to the AST node' do
        expected = {"data" => {"contextAstNodeName" => "GraphQL::Language::Nodes::Field"}}
        assert_equal(expected, query.result)
      end
    end
  end

  describe "query variables" do
    let(:query_string) {%|
      query getCheese($cheeseId: Int!){
        cheese(id: $cheeseId) { flavor }
      }
    |}

    describe "when they can be coerced" do
      let(:query_variables) { {"cheeseId" => 2.0} }

      it "coerces them on the way in" do
        assert("Gouda", result["data"]["cheese"]["flavor"])
      end
    end

    describe "when they can't be coerced" do
      let(:query_variables) { {"cheeseId" => "2"} }

      it "raises an error" do
        assert(result["errors"][0]["message"].include?(%{Couldn't coerce "2" to Int}))
      end
    end
  end
end
