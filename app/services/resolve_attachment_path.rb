# frozen_string_literal: true

module LockedCV
  # Resolves attachment storage routes under the controlled local upload root.
  class ResolveAttachmentPath
    class UnsafePathError < StandardError; end
    class MissingFileError < StandardError; end

    STORAGE_ROOT = File.expand_path('storage/uploads', Dir.pwd)

    def self.call(route:)
      raise UnsafePathError if route.to_s.strip.empty?
      raise UnsafePathError if File.absolute_path?(route.to_s)

      validated_path(full_path_for(route))
    end

    def self.inside_storage_root?(path)
      root = File.realpath(STORAGE_ROOT)
      path == root || path.start_with?("#{root}#{File::SEPARATOR}")
    rescue Errno::ENOENT
      path == STORAGE_ROOT || path.start_with?("#{STORAGE_ROOT}#{File::SEPARATOR}")
    end
    private_class_method :inside_storage_root?

    def self.full_path_for(route)
      File.expand_path(route.to_s, STORAGE_ROOT)
    end
    private_class_method :full_path_for

    def self.validated_path(full_path)
      raise UnsafePathError unless inside_storage_root?(full_path)
      raise MissingFileError unless File.file?(full_path)

      real_path = File.realpath(full_path)
      raise UnsafePathError unless inside_storage_root?(real_path)

      real_path
    end
    private_class_method :validated_path
  end
end
