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

    def resolve(podfile, dependencies = nil)
      @specs = {}
      @podfile = podfile
      find_dependency_sets(@podfile, dependencies)
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

          # See if the spec matches the platform of the project and let the spec
          # load any platform specific settings.
          if spec.platform.nil? || spec.platform == @podfile.platform
            spec.apply_platform(@podfile.platform)
          else
            raise Informative, "The platform required by the Podfile (:#{@podfile.platform}) " \
                               "does not match that of #{spec} (:#{spec.platform})"
          end

          @specs[spec.name] = spec
          # And recursively load the dependencies of the spec.
          find_dependency_sets(spec)
        end
      end
    end
  end
end
