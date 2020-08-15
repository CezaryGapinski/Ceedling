require 'reportinator_helper'

class GcovrReportinator
  attr_reader :merge_coverages_enabled

  def initialize(system_objects)
    @ceedling = system_objects
    @reportinator_helper = ReportinatorHelper.new
    @merge_coverages_enabled = false
    @intermediate_coverage_files = []
    @use_generated_gcov_files = false
    @current_coverage_step = 0
  end


  # Generate the gcovr report(s) specified in the options.
  def make_reports(opts)
    # Get the gcovr version number.
    gcovr_version_info = get_gcovr_version()

    # Build the common gcovr arguments.
    args_common = args_builder_common(opts)
    args = args_common

    if (gcovr_version_info[0] >= 4) && (gcovr_version_info[1] >= 2)
      if @merge_coverages_enabled
        summary_file = form_test_step_json_filepath('summary_report', @current_coverage_step)
        print "Creating gcovr JSON summary report in: #{summary_file}\n"
        STDOUT.flush
        run(args_common + "--json-pretty --output #{summary_file}")
        @intermediate_coverage_files << summary_file

        args += args_builder_add_tracefiles(@intermediate_coverage_files)
        args_common = args
      end
      # gcovr version 4.2 and later supports generating multiple reports with a single call.
      args += args_builder_cobertura(opts, false)
      args += args_builder_sonarqube(opts, false)
      # Note: In gcovr 4.2, the JSON report is output only when the --output option is specified.
      # Hopefully we can remove --output after a future gcovr release.
      args += args_builder_json(opts, true)
      # As of gcovr version 4.2, the --html argument must appear last.
      args += args_builder_html(opts, false)

      print "Creating gcov results report(s) in '#{GCOV_ARTIFACTS_PATH}'... "
      STDOUT.flush

      # Generate the report(s).
      run(args)
    else
      # gcovr version 4.1 and earlier supports HTML and Cobertura XML reports.
      # It does not support SonarQube and JSON reports.
      # Reports must also be generated separately.
      args_cobertura = args_builder_cobertura(opts, true)
      args_html = args_builder_html(opts, true)

      if args_html.length > 0
        print "Creating a gcov HTML report in '#{GCOV_ARTIFACTS_PATH}'... "
        STDOUT.flush

        # Generate the HTML report.
        run(args_common + args_html)
      end

      if args_cobertura.length > 0
        print "Creating a gcov XML report in '#{GCOV_ARTIFACTS_PATH}'... "
        STDOUT.flush

        # Generate the Cobertura XML report.
        run(args_common + args_cobertura)
      end
    end

    # Determine if the gcovr text report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::TEXT)
      make_text_report(opts, args_common)
    end
  end


  def support_deprecated_options(opts)
    # Support deprecated :html_report: and ":html_report_type: basic" options.
    if !is_report_enabled(opts, ReportTypes::HTML_BASIC) && (opts[:gcov_html_report] || (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("basic") == 0))
      opts[:gcov_reports].push(ReportTypes::HTML_BASIC)
    end

    # Support deprecated ":html_report_type: detailed" option.
    if !is_report_enabled(opts, ReportTypes::HTML_DETAILED) && (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("detailed") == 0)
      opts[:gcov_reports].push(ReportTypes::HTML_DETAILED)
    end

    # Support deprecated :xml_report: option.
    if opts[:gcov_xml_report]
      opts[:gcov_reports].push(ReportTypes::COBERTURA)
    end

    # Default to HTML basic report when no report types are defined.
    if opts[:gcov_reports].empty? && opts[:gcov_html_report_type].nil? && opts[:gcov_xml_report].nil?
      opts[:gcov_reports] = [ReportTypes::HTML_BASIC]

      puts "In your project.yml, define one or more of the"
      puts "following to specify which reports to generate."
      puts "For now, creating only an #{ReportTypes::HTML_BASIC} report."
      puts ""
      puts ":gcov:"
      puts "  :reports:"
      puts "    - #{ReportTypes::HTML_BASIC}"
      puts "    - #{ReportTypes::HTML_DETAILED}"
      puts "    - #{ReportTypes::TEXT}"
      puts "    - #{ReportTypes::COBERTURA}"
      puts "    - #{ReportTypes::SONARQUBE}"
      puts "    - #{ReportTypes::JSON}"
      puts ""
    end
  end


  def check_merge_coverages_enable
    opts = @ceedling[:configurator].project_config_hash
    gcovr_opts = get_opts(opts)
    if gcovr_opts[:merge_coverages]
        # Get the gcovr version number.
        gcovr_version_info = get_gcovr_version()
        if (gcovr_version_info[0] >= 4) && (gcovr_version_info[1] >= 2)
          @merge_coverages_enabled = true
        else
          @ceedling[:streaminator].stderr_puts("Gcovr >=4.2 required to merge intermediate results\n")
          exit(-1)
        end
    end
  end


  def generate_intermediate_coverage(source, object)
    if @merge_coverages_enabled && File.exist?(object.ext(GCOV_DATA_COUNT_EXTENSION))
      result_file = form_test_step_json_filepath(source, @current_coverage_step)
      @current_coverage_step = @current_coverage_step + 1
      generate_intermediate_json(source, @use_generated_gcov_files, result_file)
      @use_generated_gcov_files = true
      @intermediate_coverage_files << result_file
    end
  end


  def post_test_fixture_execute
      @use_generated_gcov_files = false
  end


  private

  GCOVR_SETTING_PREFIX = "gcov_gcovr"

  # Build the gcovr report generation common arguments.
  def args_builder_common(opts)
    gcovr_opts = get_opts(opts)

    args = ""
    args += "--root \"#{gcovr_opts[:report_root] || '.'}\" "
    args += "--config \"#{gcovr_opts[:config_file]}\" " unless gcovr_opts[:config_file].nil?
    args += "--filter \"#{gcovr_opts[:report_include]}\" " unless gcovr_opts[:report_include].nil?
    args += "--exclude \"#{gcovr_opts[:report_exclude] || GCOV_FILTER_EXCLUDE}\" "
    args += "--gcov-filter \"#{gcovr_opts[:gcov_filter]}\" " unless gcovr_opts[:gcov_filter].nil?
    args += "--gcov-exclude \"#{gcovr_opts[:gcov_exclude]}\" " unless gcovr_opts[:gcov_exclude].nil?
    args += "--exclude-directories \"#{gcovr_opts[:exclude_directories]}\" " unless gcovr_opts[:exclude_directories].nil?
    args += "--branches " if gcovr_opts[:branches].nil? || gcovr_opts[:branches] # Defaults to enabled.
    args += "--sort-uncovered " if gcovr_opts[:sort_uncovered]
    args += "--sort-percentage " if gcovr_opts[:sort_percentage].nil? || gcovr_opts[:sort_percentage] # Defaults to enabled.
    args += "--print-summary " if gcovr_opts[:print_summary]
    args += "--gcov-executable \"#{gcovr_opts[:gcov_executable]}\" " unless gcovr_opts[:gcov_executable].nil?
    args += "--exclude-unreachable-branches " if gcovr_opts[:exclude_unreachable_branches]
    args += "--exclude-throw-branches " if gcovr_opts[:exclude_throw_branches]
    args += "--use-gcov-files " if gcovr_opts[:use_gcov_files]
    args += "--gcov-ignore-parse-errors " if gcovr_opts[:gcov_ignore_parse_errors]
    args += "--keep " if gcovr_opts[:keep]
    args += "--delete " if gcovr_opts[:delete]
    args += "-j #{gcovr_opts[:num_parallel_threads]} " if !(gcovr_opts[:num_parallel_threads].nil?) && (gcovr_opts[:num_parallel_threads].is_a? Integer)

    [:fail_under_line, :fail_under_branch, :source_encoding, :object_directory].each do |opt|
      unless gcovr_opts[opt].nil?

        value = gcovr_opts[opt]
        if (opt == :fail_under_line) || (opt == :fail_under_branch)
          if not value.is_a? Integer
            puts "Option value #{opt} has to be an integer"
            value = nil
          elsif (value < 0) || (value > 100)
            puts "Option value #{opt} has to be a percentage from 0 to 100"
            value = nil
          end
        end
        args += "--#{opt.to_s.gsub('_','-')} #{value} " unless value.nil?
      end
    end

    return args
  end


  # Build the gcovr Cobertura XML report generation arguments.
  def args_builder_cobertura(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the Cobertura XML report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::COBERTURA)
      # Determine the Cobertura XML report file name.
      artifacts_file_cobertura = GCOV_ARTIFACTS_FILE_COBERTURA
      if !(gcovr_opts[:cobertura_artifact_filename].nil?)
        artifacts_file_cobertura = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:cobertura_artifact_filename])
      elsif !(gcovr_opts[:xml_artifact_filename].nil?)
        artifacts_file_cobertura = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:xml_artifact_filename])
      end

      args += "--xml-pretty " if gcovr_opts[:xml_pretty] || gcovr_opts[:cobertura_pretty]
      args += "--xml #{use_output_option ? "--output " : ""} \"#{artifacts_file_cobertura}\" "
    end

    return args
  end


  # Build the gcovr SonarQube report generation arguments.
  def args_builder_sonarqube(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr SonarQube XML report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::SONARQUBE)
      # Determine the SonarQube XML report file name.
      artifacts_file_sonarqube = GCOV_ARTIFACTS_FILE_SONARQUBE
      if !(gcovr_opts[:sonarqube_artifact_filename].nil?)
        artifacts_file_sonarqube = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:sonarqube_artifact_filename])
      end

      args += "--sonarqube #{use_output_option ? "--output " : ""} \"#{artifacts_file_sonarqube}\" "
    end

    return args
  end


  # Build the gcovr JSON report generation arguments.
  def args_builder_json(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr JSON report is enabled. Defaults to disabled.
    if is_report_enabled(opts, ReportTypes::JSON)
      # Determine the JSON report file name.
      artifacts_file_json = GCOV_ARTIFACTS_FILE_JSON
      if !(gcovr_opts[:json_artifact_filename].nil?)
        artifacts_file_json = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:json_artifact_filename])
      end

      args += "--json-pretty " if gcovr_opts[:json_pretty]
      args += "--json #{use_output_option ? "--output " : ""} \"#{artifacts_file_json}\" "
    end

    return args
  end


  # Build the gcovr HTML report generation arguments.
  def args_builder_html(opts, use_output_option=false)
    gcovr_opts = get_opts(opts)
    args = ""

    # Determine if the gcovr HTML report is enabled. Defaults to enabled.
    html_enabled = (opts[:gcov_html_report].nil? && opts[:gcov_reports].empty?) ||
                   is_report_enabled(opts, ReportTypes::HTML_BASIC) ||
                   is_report_enabled(opts, ReportTypes::HTML_DETAILED)

    if html_enabled
      # Determine the HTML report file name.
      artifacts_file_html = GCOV_ARTIFACTS_FILE_HTML
      if !(gcovr_opts[:html_artifact_filename].nil?)
        artifacts_file_html = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:html_artifact_filename])
      end

      is_html_report_type_detailed = (opts[:gcov_html_report_type].is_a? String) && (opts[:gcov_html_report_type].casecmp("detailed") == 0)

      args += "--html-details " if is_html_report_type_detailed || is_report_enabled(opts, ReportTypes::HTML_DETAILED)
      args += "--html-title \"#{gcovr_opts[:html_title]}\" " unless gcovr_opts[:html_title].nil?
      args += "--html-absolute-paths " if !(gcovr_opts[:html_absolute_paths].nil?) && gcovr_opts[:html_absolute_paths]
      args += "--html-encoding \"#{gcovr_opts[:html_encoding]}\" " unless gcovr_opts[:html_encoding].nil?

      [:html_medium_threshold, :html_high_threshold].each do |opt|
        args += "--#{opt.to_s.gsub('_','-')} #{gcovr_opts[opt]} " unless gcovr_opts[opt].nil?
      end

      # The following option must be appended last for gcovr version <= 4.2 to properly work.
      args += "--html #{use_output_option ? "--output " : ""} \"#{artifacts_file_html}\" "
    end

    return args
  end


  # Generate a gcovr text report.
  def make_text_report(opts, args_common)
    gcovr_opts = get_opts(opts)
    args_text = ""
    message_text = "Creating a gcov text report"

    if !(gcovr_opts[:text_artifact_filename].nil?)
      artifacts_file_txt = File.join(GCOV_ARTIFACTS_PATH, gcovr_opts[:text_artifact_filename])
      args_text += "--output \"#{artifacts_file_txt}\" "
      message_text += " in '#{GCOV_ARTIFACTS_PATH}'... "
    else
      message_text += "... "
    end

    print message_text
    STDOUT.flush

    # Generate the text report.
    run(args_common + args_text)
  end


  # Get the gcovr options from the project options.
  def get_opts(opts)
    return opts[GCOVR_SETTING_PREFIX.to_sym] || {}
  end

  def args_builder_add_tracefiles(coverage_files)
    args = coverage_files.map { |item| "--add-tracefile #{item} " }
    return args.join(" ")
  end


  def generate_intermediate_json(source_file, use_generated_gcov, result_file)
    # Get the gcov options from project.yml.
    opts = @ceedling[:configurator].project_config_hash
    args = args_builder_common(opts)
    args += "--filter \"#{source_file}\" "
    if use_generated_gcov
      args += "--use-gcov-files "
    else
      args += "--keep "
    end
    args += "--json-pretty --output #{result_file} "

    print "Creating JSON gcovr previous results for #{source_file} in: #{result_file}\n"
    STDOUT.flush

    run(args)
  end


  def form_test_step_json_filepath(filepath, step)
    basename = File.basename(filepath, File.extname(filepath)) + '_step_' + step.to_s
    return File.join( GCOV_BUILD_OUTPUT_PATH, basename.ext('.json') )
  end


  # Run gcovr with the given arguments.
  def run(args)
    begin
      command = @ceedling[:tool_executor].build_command_line(TOOLS_GCOV_GCOVR_POST_REPORT, [], args)
      shell_result = @ceedling[:tool_executor].exec(command[:line], command[:options])
      @reportinator_helper.print_shell_result(shell_result)
    rescue
      # handle any unforeseen issues with called tool
      exitcode = $?.exitstatus
      show_gcovr_message(exitcode)
      exit(exitcode)
    end
  end


  # Get the gcovr version number as components.
  # Returns [major, minor].
  def get_gcovr_version()
    version_number_major = 0
    version_number_minor = 0

    command = @ceedling[:tool_executor].build_command_line(TOOLS_GCOV_GCOVR_POST_REPORT, [], "--version")
    shell_result = @ceedling[:tool_executor].exec(command[:line], command[:options])
    version_number_match_data = shell_result[:output].match(/gcovr ([0-9]+)\.([0-9]+)/)

    if !(version_number_match_data.nil?) && !(version_number_match_data[1].nil?) && !(version_number_match_data[2].nil?)
        version_number_major = version_number_match_data[1].to_i
        version_number_minor = version_number_match_data[2].to_i
    end

    return version_number_major, version_number_minor
  end


  # Show a more human-friendly message on gcovr return code
  def show_gcovr_message(exitcode)
    if ((exitcode & 2) == 2)
      puts "The line coverage is less than the minimum"
    end
    if ((exitcode & 4) == 4)
      puts "The branch coverage is less than the minimum"
    end
  end


  # Returns true if the given report type is enabled, otherwise returns false.
  def is_report_enabled(opts, report_type)
    return !(opts.nil?) && !(opts[:gcov_reports].nil?) && (opts[:gcov_reports].map(&:upcase).include? report_type.upcase)
  end

end
