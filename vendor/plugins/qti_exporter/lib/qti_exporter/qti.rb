module Qti
  PYTHON_MIGRATION_EXECUTABLE = 'migrate.py'
  EXPECTED_LOCATION = File.join(::RAILS_ROOT,'vendor', 'QTIMigrationTool', PYTHON_MIGRATION_EXECUTABLE) rescue nil
  @migration_executable = nil

  if File.exists?(EXPECTED_LOCATION)
    @migration_executable = EXPECTED_LOCATION
  elsif `#{PYTHON_MIGRATION_EXECUTABLE} --version 2>&1` =~ /qti/i
    @migration_executable = PYTHON_MIGRATION_EXECUTABLE
  end

  def self.migration_executable
    @migration_executable
  end

  # Does a JSON export of the courses
  def self.save_to_file(hash, file_name = nil)
    file_name ||= File.join('log', 'qti_export.json')
    File.open(file_name, 'w') { |file| file << hash.to_json }
    file_name
  end

  def self.convert_questions(manifest_path)
    questions = []
    doc = Nokogiri::HTML(open(manifest_path))
    doc.css('manifest resources resource[type^=imsqti_item_xmlv2p]').each do |item|
      q = AssessmentItemConverter::create_instructure_question(:manifest_node=>item, :base_dir=>File.dirname(manifest_path))
      questions << q if q
    end
    questions
  end

  def self.convert_assessments(manifest_path, is_webct=true)
    assessments = []
    doc = Nokogiri::HTML(open(manifest_path))
    doc.css('manifest resources resource[type=imsqti_assessment_xmlv2p1]').each do |item|
      a = AssessmentTestConverter.new(item, File.dirname(manifest_path), is_webct).create_instructure_quiz
      assessments << a if a
    end
    assessments
  end

  def self.get_conversion_command(out_dir, manifest_file)
    "\"#{@migration_executable}\" --ucvars --nogui --overwrite --cpout=#{out_dir.gsub(/ /, "\\ ")} #{manifest_file.gsub(/ /, "\\ ")} 2>&1"
  end

end