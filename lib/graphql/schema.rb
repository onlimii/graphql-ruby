# A GraphQL schema which may be queried with {GraphQL::Query}.
class GraphQL::Schema
  extend Forwardable

  DIRECTIVES = [GraphQL::Directive::SkipDirective, GraphQL::Directive::IncludeDirective]
  DYNAMIC_FIELDS = ["__type", "__typename", "__schema"]

  attr_reader :query, :mutation, :directives, :static_validator
  # Override these if you don't want the default executor:
  attr_accessor :query_execution_strategy, :mutation_execution_strategy

  # @return [Array<#call>] Middlewares suitable for MiddlewareChain, applied to fields during execution
  attr_reader :middleware

  # @param query [GraphQL::ObjectType]  the query root for the schema
  # @param mutation [GraphQL::ObjectType, nil] the mutation root for the schema
  def initialize(query:, mutation: nil)
    @query    = query
    @mutation = mutation
    @directives = DIRECTIVES.reduce({}) { |m, d| m[d.name] = d; m }
    @static_validator = GraphQL::StaticValidation::Validator.new(schema: self)
    @rescue_middleware = GraphQL::Schema::RescueMiddleware.new
    @middleware = [@rescue_middleware]
    # Default to the built-in execution strategy:
    self.query_execution_strategy = GraphQL::Query::SerialExecution
    self.mutation_execution_strategy = GraphQL::Query::SerialExecution
  end

  def_delegators :@rescue_middleware, :rescue_from, :remove_handler

  # @return [GraphQL::Schema::TypeMap] `{ name => type }` pairs of types in this schema
  def types
    @types ||= TypeReducer.find_all([query, mutation, GraphQL::Introspection::SchemaType].compact)
  end

  # Execute a query on itself.
  # See {Query#initialize} for arguments.
  # @return [Hash] query result, ready to be serialized as JSON
  def execute(*args)
    query = GraphQL::Query.new(self, *args)
    query.result
  end

  # Resolve field named `field_name` for type `parent_type`.
  # Handles dynamic fields `__typename`, `__type` and `__schema`, too
  def get_field(parent_type, field_name)
    defined_field = parent_type.fields[field_name]
    if defined_field
      defined_field
    elsif field_name == "__typename"
      GraphQL::Introspection::TypenameField.create(parent_type)
    elsif field_name == "__schema" && parent_type == query
      GraphQL::Introspection::SchemaField.create(self)
    elsif field_name == "__type" && parent_type == query
      GraphQL::Introspection::TypeByNameField.create(self.types)
    else
      nil
    end
  end

  class InvalidTypeError < StandardError
    def initialize(type, errors)
      super("Type #{type.respond_to?(:name) ? type.name :  "Unnamed type" } is invalid: #{errors.join(", ")}")
    end
  end
end

require 'graphql/schema/each_item_validator'
require 'graphql/schema/field_validator'
require 'graphql/schema/implementation_validator'
require 'graphql/schema/middleware_chain'
require 'graphql/schema/rescue_middleware'
require 'graphql/schema/type_reducer'
require 'graphql/schema/type_map'
require 'graphql/schema/type_validator'
