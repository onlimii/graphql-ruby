module GraphQL
  # The parent for all type classes.
  class BaseType
    include GraphQL::DefinitionHelpers::NonNullWithBang
    include GraphQL::DefinitionHelpers::DefinedByConfig

    # @param other [GraphQL::BaseType] compare to this object
    # @return [Boolean] are these types equivalent? (incl. non-null, list)
    def ==(other)
      if other.is_a?(GraphQL::BaseType)
        self.to_s == other.to_s
      else
        super
      end
    end

    # If this type is modifying an underlying type,
    # return the underlying type. (Otherwise, return `self`.)
    def unwrap
      self
    end

    module ModifiesAnotherType
      def unwrap
        self.of_type.unwrap
      end
    end

    # Find out which possible type to use for `value`.
    # Returns self if there are no possible types (ie, not Union or Interface)
    def resolve_type(value)
      self
    end

    module HasPossibleTypes
      # Return the implementing type for `object`.
      # The default implementation assumes that there's a type with the same name as `object.class.name`.
      # Maybe you'll need to override this in your own interfaces!
      #
      # @param object [Object] the object which needs a type to expose it
      # @return [GraphQL::ObjectType] the type which should expose `object`
      def resolve_type(object)
        instance_exec(object, &@resolve_type_proc)
      end

      # The default implementation of {#resolve_type} gets `object.class.name`
      # and finds a type with the same name
      DEFAULT_RESOLVE_TYPE = -> (object) {
        type_name = object.class.name
        possible_types.find {|t| t.name == type_name}
      }

      def resolve_type=(new_proc)
        @resolve_type_proc = new_proc || DEFAULT_RESOLVE_TYPE
      end

      def include?(type)
        possible_types.include?(type)
      end
    end

    # Print the human-readable name of this type using the query-string naming pattern
    def to_s
      name
    end

    alias :inspect :to_s

    # Coerce `input_value` according to this type's `coerce` method.
    # Raise an error if the value becomes nil.
    # @param [Object] Incoming query value
    # @return [Object] Coerced value for query execution
    def coerce_input!(input_value)
      coerced_value = coerce_input(input_value)

      if coerced_value.nil?
        raise GraphQL::ExecutionError.new("Couldn't coerce #{input_value.inspect} to #{self.unwrap.name}")
      end

      coerced_value
    end
  end
end
