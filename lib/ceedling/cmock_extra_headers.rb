

class CmockExtraHeaders

  attr_reader :extra_headers

  constructor :configurator, :preprocessinator_includes_handler, :test_includes_extractor, :file_path_utils, :yaml_wrapper, :file_wrapper

  def setup 
    @extra_headers = {}
    @extra_headers_backup = {}
  end

  def parse_source_headers(sources, mocks)
    if not include_inlines_enabled
      return
    end

    prepare_headers(sources)
    sources.each do |source|
      includes = []
      if (@configurator.project_use_test_preprocessor)
        includes = @yaml_wrapper.load(@file_path_utils.form_preprocessed_deep_includes_list_filepath(source))
      else
        includes = @test_includes_extractor.lookup_includes_list(source)
      end
      prepare_real_headers_from_mocks(source, includes, mocks)
    end
  end

  def parse_test_headers(test, mocks)
    if not include_inlines_enabled
      return
    end

    headers_list = mocks.clone
    headers_list.map! { |mock| File.basename(mock, ".*").sub(/#{@configurator.cmock_mock_prefix}/, '') }
    extra_headers_list = {}
    if not headers_list.empty?
      extra_headers_list = @file_path_utils.form_mocks_header_filelist(headers_list).to_a
    end

    @extra_headers[test] = extra_headers_list
  end

  def update_extra_headers(source)
    if not include_inlines_enabled
      return
    end

    @extra_headers_backup = Array.new(COLLECTION_TEST_EXTRA_INCLUDE_FILES)
    collection = Array.new(COLLECTION_TEST_EXTRA_INCLUDE_FILES)
    if (not @extra_headers.empty?)
      if (not @extra_headers[source].nil?) && (not @extra_headers[source].empty?)
        collection.append(@extra_headers[source])
        COLLECTION_TEST_EXTRA_INCLUDE_FILES.replace(collection)
      end
    end
  end

  def recover_extra_headers
    if not include_inlines_enabled
      return
    end

    COLLECTION_TEST_EXTRA_INCLUDE_FILES.replace(@extra_headers_backup)
  end

  private

  def include_inlines_enabled
    return @configurator.get_cmock_config.has_key?(:treat_inlines) && @configurator.get_cmock_config[:treat_inlines] == :include
  end

  def prepare_headers(sources)
    if (@configurator.project_use_test_preprocessor)
      sources.each do |source|
        # update timestamp for rake task prerequisites and always update headers
        @file_wrapper.touch(@configurator.project_test_force_rebuild_filepath, :mtime => Time.now + 10)
        @preprocessinator_includes_handler.invoke_shallow_includes_list(source, true)
      end
    else
      sources.each do |source|
        @test_includes_extractor.parse_test_file(source)
      end
    end
  end

  def prepare_real_headers_from_mocks(source, includes, mocks)
    includes_list = includes.clone
    includes_list.map! { |item| File.basename(item, @configurator.extension_header)}
    mocks_list = mocks.clone
    mocks_list.map! { |mock| File.basename(mock, ".*").sub(/#{@configurator.cmock_mock_prefix}/, '') }
    intersection = includes_list & mocks_list
    extra_headers_list = {}
    if not intersection.empty?
      extra_headers_list = @file_path_utils.form_mocks_header_filelist(intersection).to_a
    end
    @extra_headers[source] = extra_headers_list
  end

end
