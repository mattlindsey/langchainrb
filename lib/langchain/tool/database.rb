module Langchain::Tool
  class Database < Base
    #
    # Connects to a database, executes SQL queries, and outputs DB schema for Agents to use
    #
    # Gem requirements: gem "sequel", "~> 5.68.0"
    #

    NAME = "database"

    description <<~DESC
      Useful for getting the result of a database query.

      The input to this tool should be valid SQL.
    DESC

    attr_reader :db, :requested_tables, :excluded_tables

    #
    # Establish a database connection
    #
    # @param connection_string [String] Database connection info, e.g. 'postgres://user:password@localhost:5432/db_name'
    # @param tables [Array<Symbol>] The tables to use. Will use all if empty.
    # @param except_tables [Array<Symbol>] The tables to exclude. Will exclude none if empty.

    # @return [Database] Database object
    #
    def initialize(connection_string:, tables: [], exclude_tables: [])
      depends_on "sequel"

      raise StandardError, "connection_string parameter cannot be blank" if connection_string.empty?

      @db = Sequel.connect(connection_string)
      @requested_tables = tables
      @excluded_tables = exclude_tables
    end

    #
    # Returns the database schema
    #
    # @return [String] schema
    #
    def dump_schema
      Langchain.logger.info("Dumping schema tables and keys", for: self.class)
      schema = ""
      db.tables.each do |table|
        next if excluded_tables.include?(table)
        next unless requested_tables.empty? || requested_tables.include?(table)

        primary_key_columns = []
        primary_key_column_count = db.schema(table).count { |column| column[1][:primary_key] == true }

        schema << "CREATE TABLE #{table}(\n"
        db.schema(table).each do |column|
          schema << "#{column[0]} #{column[1][:type]}"
          if column[1][:primary_key] == true
            schema << " PRIMARY KEY" if primary_key_column_count == 1
          else
            primary_key_columns << column[0]
          end
          schema << ",\n" unless column == db.schema(table).last && primary_key_column_count == 1
        end
        if primary_key_column_count > 1
          schema << "PRIMARY KEY (#{primary_key_columns.join(",")})"
        end
        db.foreign_key_list(table).each do |fk|
          schema << ",\n" if fk == db.foreign_key_list(table).first
          schema << "FOREIGN KEY (#{fk[:columns][0]}) REFERENCES #{fk[:table]}(#{fk[:key][0]})"
          schema << ",\n" unless fk == db.foreign_key_list(table).last
        end
        schema << ");\n"
      end
      schema
    end

    #
    # Evaluates a sql expression
    #
    # @param input [String] sql expression
    # @return [Array] results
    #
    def execute(input:)
      Langchain.logger.info("Executing \"#{input}\"", for: self.class)

      db[input].to_a
    rescue Sequel::DatabaseError => e
      Langchain.logger.error(e.message, for: self.class)
      e.message
    end
  end
end
