module Pod
  class Resolver
    attr_reader :cached_sources, :cached_sets

    def initialize(podfile)
      @podfile = podfile
      @cached_sets = {}
      @cached_sources = Source::Aggregate.new
    end

    # This method will start the lookup from the given dependencies, which are
    # those required by a Podfile.
    #
    # It defaults to resolve the dependencies of the `@podfile`.
    def resolve(dependencies = @podfile.dependencies)
      # This holds the data for each `resolve` invocation.
      @specs = {}
      # Resolve
      find_dependency_sets(@podfile, dependencies)
      # Sort result by name and associate `part_of` specs with the other.
      @specs.values.sort_by(&:name).each do |spec|
        if spec.part_of_other_pod?
          spec.part_of_specification = @cached_sets[spec.part_of.name].specification
        end
      end
    end

    private

    def find_cached_set(dependency)
      @cached_sets[dependency.name] ||= begin
        if external_spec = dependency.specification
          Specification::Set::External.new(external_spec)
        else
          @cached_sources.search(dependency)
        end
      end
    end

    def find_dependency_sets(dependent_specification, dependencies)
      dependencies.each do |dependency|
        set = find_cached_set(dependency)
        set.required_by(dependent_specification)
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
          find_dependency_sets(spec, spec.dependencies)
        end
      end
    end
  end
end
