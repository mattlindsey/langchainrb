# frozen_string_literal: true

module Langchain::LLM
  #
  # Wrapper around the HuggingFace Inference API: https://huggingface.co/inference-api
  #
  # Gem requirements:
  #     gem "hugging-face", "~> 0.3.4"
  #
  # Usage:
  #     hf = Langchain::LLM::HuggingFace.new(api_key: ENV["HUGGING_FACE_API_KEY"])
  #
  class HuggingFace < Base
    # The gem does not currently accept other models:
    # https://github.com/alchaplinsky/hugging-face/blob/main/lib/hugging_face/inference_api.rb#L32-L34
    DEFAULTS = {
      temperature: 0.0,
      embeddings_model_name: "sentence-transformers/all-MiniLM-L6-v2",
      dimensions: 384 # Vector size generated by the above model
    }.freeze

    #
    # Intialize the HuggingFace LLM
    #
    # @param api_key [String] The API key to use
    #
    def initialize(api_key:)
      depends_on "hugging-face", req: "hugging_face"

      @client = ::HuggingFace::InferenceApi.new(api_token: api_key)
    end

    #
    # Generate an embedding for a given text
    #
    # @param text [String] The text to embed
    # @return [Langchain::LLM::HuggingFaceResponse] Response object
    #
    def embed(text:)
      response = client.embedding(
        input: text,
        model: DEFAULTS[:embeddings_model_name]
      )
      Langchain::LLM::HuggingFaceResponse.new(response, model: DEFAULTS[:embeddings_model_name])
    end
  end
end
