# frozen_string_literal: true

module Langchain::Vectorsearch
  class Weaviate < Base
    #
    # Wrapper around Weaviate
    #
    # Gem requirements: gem "weaviate-ruby", "~> 0.8.0"
    #
    # Usage:
    # weaviate = Langchain::Vectorsearch::Weaviate.new(url:, api_key:, index_name:, llm:, llm_api_key:)
    #

    # Initialize the Weaviate adapter
    # @param url [String] The URL of the Weaviate instance
    # @param api_key [String] The API key to use
    # @param index_name [String] The capitalized name of the index to use
    # @param llm [Object] The LLM client to use
    # @param model_service [Symbol] The LLM service to use (e.g. :openai)
    # @param model_api_key [String] The LLM API key to use to vectorize the texts
    def initialize(url:, api_key:, index_name:, llm:, model_service:, model_api_key:)
      depends_on "weaviate-ruby"
      require "weaviate"

      @model_service = model_service
      @client = ::Weaviate::Client.new(
        url: url,
        api_key: api_key,
        model_service: model_service,
        model_service_api_key: model_api_key
      )

      # Weaviate requires the class name to be Capitalized: https://weaviate.io/developers/weaviate/configuration/schema-configuration#create-a-class
      # TODO: Capitalize index_name
      @index_name = index_name

      super(llm: llm)
    end

    # Add a list of texts to the index
    # @param texts [Array] The list of texts to add
    # @return [Hash] The response from the server
    def add_texts(texts:, ids: [])
      client.objects.batch_create(
        objects: weaviate_objects(texts, ids)
      )
    end

    # Update a list of texts in the index
    # @param texts [Array] The list of texts to update
    # @return [Hash] The response from the server
    def update_texts(texts:, ids:)
      uuids = []

      # Retrieve the UUIDs of the objects to update
      Array(texts).map.with_index do |text, i|
        record = client.query.get(
          class_name: index_name,
          fields: "_additional { id }",
          where: "{ path: [\"__id\"], operator: Equal, valueString: \"#{ids[i]}\" }"
        )
        uuids.push record[0].dig("_additional", "id")
      end

      # Update the objects
      texts.map.with_index do |text, i|
        client.objects.update(
          class_name: index_name,
          id: uuids[i],
          properties: {
            __id: ids[i].to_s,
            content: text
          },
          vector: llm.embed(text: text)
        )
      end
    end

    # Create default schema
    # To use a vectorizer other than "none" you need to set ENABLE_MODULES on the Weaviate server
    def create_default_schema
      # TODO: Make this a hash lookup
      vectorizer = if @model_service == :openai
        "text2vec-openai"
      elsif @model_service == :azure_openai
        "text2vec-openai"
      elsif @model_service == :cohere
        "text2vec-cohere"
      elsif @model_service == :huggingface
        "text2vec-huggingface"
      else
        "none"
      end

      client.schema.create(
        class_name: index_name,
        vectorizer: vectorizer,
        properties: [
          # __id to be used a pointer to the original document
          {dataType: ["string"], name: "__id"}, # '_id' is a reserved property name (single underscore)
          {dataType: ["text"], name: "content"}
        ]
      )
    end

    # Return documents similar to the query
    # @param query [String] The query to search for
    # @param k [Integer|String] The number of results to return
    # @param distance [Integer|String] The maximum distance to search for
    # @return [Hash] The search results
    def similarity_search(query:, k: 4, distance: nil)
      if distance
        near_text = "{ concepts: \"#{query}\" distance: #{distance} }"

        client.query.get(
          class_name: index_name,
          near_text: near_text,
          limit: k.to_s,
          fields: "content _additional { id distance}"
        )
      else
        embedding = llm.embed(text: query)

        similarity_search_by_vector(embedding: embedding, k: k)
      end
    end

    # Return documents similar to the vector
    # @param embedding [Array] The vector to search for
    # @param k [Integer|String] The number of results to return
    # @return [Hash] The search results
    def similarity_search_by_vector(embedding:, k: 4)
      near_vector = "{ vector: #{embedding} }"

      client.query.get(
        class_name: index_name,
        near_vector: near_vector,
        limit: k.to_s,
        fields: "__id content _additional { id }"
      )
    end

    # Ask a question and return the answer
    # @param question [String] The question to ask
    # @return [Hash] The answer
    def ask(question:)
      search_results = similarity_search(query: question)

      context = search_results.map do |result|
        result.dig("content").to_s
      end
      context = context.join("\n---\n")

      prompt = generate_prompt(question: question, context: context)

      llm.chat(prompt: prompt)
    end

    private

    def weaviate_objects(texts, ids = [])
      Array(texts).map.with_index do |text, i|
        weaviate_object(text, ids[i])
      end
    end

    def weaviate_object(text, id = nil)
      {
        class: index_name,
        properties: {
          __id: id.to_s,
          content: text
        },
        vector: llm.embed(text: text)
      }
    end
  end
end
