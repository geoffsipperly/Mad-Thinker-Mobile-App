// Bend Fly Shop

// ForumModels.swift
import Foundation

struct ForumCategory: Identifiable, Decodable, Hashable {
  let id: String
  let name: String
  let description: String?
  let sort_order: Int?
  let created_at: String?
  let updated_at: String?
}

struct ForumProfile: Decodable, Hashable {
  let id: String
  let first_name: String?
  let last_name: String?
  let user_type: String?
}

struct ForumThread: Identifiable, Decodable, Hashable {
  let id: String
  let category_id: String
  let user_id: String?
  let title: String
  let is_pinned: Bool?
  let is_locked: Bool?
  let view_count: Int?
  let created_at: String?
  let profiles: ForumProfile?
  let author_first_name: String?
  let author_last_name: String?
  let author_user_type: String?
}

/// Media attachment on a forum post (image or video)
struct ForumMedia: Identifiable, Decodable, Hashable {
  let id: String
  let file_name: String
  let file_type: String      // "image" or "video"
  let mime_type: String
  let publicUrl: String

  var isVideo: Bool { file_type == "video" }
  var isImage: Bool { file_type == "image" }
}

struct ForumPost: Identifiable, Decodable, Hashable {
  let id: String
  let thread_id: String
  let user_id: String?
  let content: String
  let is_edited: Bool?
  let created_at: String?
  let profiles: ForumProfile?
  let author_first_name: String?
  let author_last_name: String?
  let author_user_type: String?
  let media: [ForumMedia]?
}

/// Media attachment for uploading (used in create/update requests)
struct MediaAttachment: Encodable {
  let fileName: String
  let mimeType: String
  let data_base64: String
}
