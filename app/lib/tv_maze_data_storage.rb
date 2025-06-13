require "fileutils"
require "json"

module TvMazeDataStorage
  LOCAL_STORAGE_PATH = Rails.root.join("storage", "tvmaze_data.json").freeze
  S3_BUCKET = ENV.fetch("TV_MAZE_S3_BUCKET", "tv-shows-api-data").freeze
  S3_KEY = ENV.fetch("TV_MAZE_S3_KEY", "tvmaze_data.json").freeze

  class << self
    def read_data
      Rails.env.production? ? read_from_s3 : read_from_local
    end

    def write_data(data)
      Rails.env.production? ? write_to_s3(data) : write_to_local(data)
    end

    def data_exists?
      Rails.env.production? ? s3_file_exists? : local_file_exists?
    end

    def delete_data
      Rails.env.production? ? delete_from_s3 : delete_from_local
    end

    private

    def read_from_local
      return nil unless local_file_exists?

      content = File.read(LOCAL_STORAGE_PATH)
      JSON.parse(content)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse local storage file: #{e.message}"
      nil
    end

    def write_to_local(data)
      FileUtils.mkdir_p(File.dirname(LOCAL_STORAGE_PATH))
      File.write(LOCAL_STORAGE_PATH, JSON.pretty_generate(data))
      true
    rescue StandardError => e
      Rails.logger.error "Failed to write to local storage: #{e.message}"
      false
    end

    def local_file_exists?
      File.exist?(LOCAL_STORAGE_PATH)
    end

    def delete_from_local
      FileUtils.rm_f(LOCAL_STORAGE_PATH)
      true
    rescue StandardError => e
      Rails.logger.error "Failed to delete local storage file: #{e.message}"
      false
    end

    def read_from_s3
      return nil unless s3_client_available?

      response = s3_client.get_object(bucket: S3_BUCKET, key: S3_KEY)
      JSON.parse(response.body.read)
    rescue Aws::S3::Errors::NoSuchKey
      nil
    rescue StandardError => e
      Rails.logger.error "Failed to read from S3: #{e.message}"
      nil
    end

    def write_to_s3(data)
      return write_to_local(data) unless s3_client_available?

      s3_client.put_object(
        bucket: S3_BUCKET,
        key: S3_KEY,
        body: JSON.pretty_generate(data),
        content_type: "application/json"
      )
      true
    rescue StandardError => e
      Rails.logger.error "Failed to write to S3: #{e.message}"
      # Fallback to local storage
      write_to_local(data)
    end

    def s3_file_exists?
      return local_file_exists? unless s3_client_available?

      s3_client.head_object(bucket: S3_BUCKET, key: S3_KEY)
      true
    rescue Aws::S3::Errors::NotFound
      false
    rescue StandardError => e
      Rails.logger.error "Failed to check S3 file existence: #{e.message}"
      false
    end

    def delete_from_s3
      return delete_from_local unless s3_client_available?

      s3_client.delete_object(bucket: S3_BUCKET, key: S3_KEY)
      true
    rescue StandardError => e
      Rails.logger.error "Failed to delete from S3: #{e.message}"
      false
    end

    def s3_client_available?
      @s3_available ||= begin
        require "aws-sdk-s3"
        true
      rescue LoadError
        Rails.logger.warn "AWS SDK not available, falling back to local storage"
        false
      end
    end

    def s3_client
      @s3_client ||= begin
        return nil unless s3_client_available?

        options = {}
        options[:region] = ENV["AWS_REGION"] if ENV["AWS_REGION"]

        # Use instance profile credentials in production, local credentials otherwise
        unless Rails.env.production?
          options[:access_key_id] = ENV["AWS_ACCESS_KEY_ID"]
          options[:secret_access_key] = ENV["AWS_SECRET_ACCESS_KEY"]
        end

        Aws::S3::Client.new(options)
      end
    end
  end
end
