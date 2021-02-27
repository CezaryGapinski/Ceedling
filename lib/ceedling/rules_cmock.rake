

rule(/#{CMOCK_MOCK_PREFIX}[^\/\\]+#{'\\'+EXTENSION_SOURCE}$/ => [
    proc do |task_name|
      @ceedling[:file_finder].find_header_input_for_mock_file(task_name)
    end  
  ]) do |mock|

  cmock_config = @ceedling[:configurator].get_cmock_config

  if cmock_config.has_key?(:treat_inlines) && cmock_config[:treat_inlines] == :include
    @ceedling[:generator].generate_mock(TEST_SYM, @ceedling[:file_finder].find_header_file_from_mock(mock.source))
    mock_path = cmock_config[:mock_path]
    if cmock_config[:subdir]
      mock_path = "#{mock_path}/#{cmock_config[:subdir]}"
    end
    module_name = File.basename(mock.source)
    full_path_for_mock = "#{mock_path}/#{module_name}"
    temp_filepath = @ceedling[:file_path_utils].form_temp_path(full_path_for_mock, '_inline_header_')
    FileUtils.cp(full_path_for_mock, temp_filepath)
  end

  @ceedling[:generator].generate_mock(TEST_SYM, mock.source)
  if cmock_config.has_key?(:treat_inlines) && cmock_config[:treat_inlines] == :include
    FileUtils.cp(temp_filepath, full_path_for_mock)
  end
end
