module Pod
  class Resolver
    # A Resolver::Context caches specification sets and is used by the resolver
    # to ensure that extra dependencies on a set are added to the same instance.
    #
    # In addition, the context is later on used by Specification to lookup other
    # specs, like the on they are a part of.
    class Context
      attr_reader :sources, :sets

      def initialize
        @sets = {}
        @sources = Source::Aggregate.new
      end

      def find_dependency_set(dependency)
        @sets[dependency.name] ||= begin
          if external_spec = dependency.specification
            Specification::Set::External.new(external_spec)
          else
            @sources.search(dependency)
          end
        end
      end
    end

    attr_reader :context

    def initialize
      @context = Context.new
    end

    def resolve(specification, top_level_dependencies = nil)
      @specs = {}
      @top_level_specification = specification
      find_dependency_sets(specification, top_level_dependencies)
      @specs.values.sort_by(&:name).each do |spec|
        if spec.part_of_other_pod?
          # Specification doesn't need to know more about a context, so we assign
          # the other specification, of which this pod is a part, to the spec.
          spec.part_of_specification = @context.sets[spec.part_of.name].specification
        end
      end
    end

    private

    def find_dependency_sets(specification, dependencies = nil)
      (dependencies || specification.dependencies).each do |dependency|
        set = @context.find_dependency_set(dependency)
        set.required_by(specification)
        # Ensure we don't resolve the same spec twice
        unless @specs.has_key?(dependency.name)
          # Get a reference to the spec that’s actually being loaded.
          # If it’s a subspec dependency, e.g. 'RestKit/Network', then
          # find that subspec.
          spec = set.specification
          if dependency.subspec_dependency?
            spec = spec.subspec_by_name(dependency.name)
          end
          validate_platform!(spec)
          @specs[spec.name] = spec
          # And recursively load the dependencies of the spec.
          find_dependency_sets(spec)
        end
      end
    end

    def validate_platform!(spec)
      unless spec.platform.nil? || spec.platform == @top_level_specification.platform
        raise Informative, "The platform required by the Podfile (:#{@top_level_specification.platform}) " \
                           "does not match that of #{spec} (:#{spec.platform})"
      end
    end
  end
end
