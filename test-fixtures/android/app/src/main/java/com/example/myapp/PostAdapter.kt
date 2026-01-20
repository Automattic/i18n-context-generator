package com.example.myapp

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView

data class Post(
    val id: String,
    val content: String,
    val likesCount: Int,
    val commentsCount: Int,
    val isLiked: Boolean
)

class PostAdapter(
    private val onLikeClick: (Post) -> Unit,
    private val onShareClick: (Post) -> Unit,
    private val onDeleteClick: (Post) -> Unit
) : ListAdapter<Post, PostAdapter.PostViewHolder>(PostDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PostViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_post, parent, false)
        return PostViewHolder(view)
    }

    override fun onBindViewHolder(holder: PostViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class PostViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {

        private val contentText: TextView = itemView.findViewById(R.id.content_text)
        private val likeButton: Button = itemView.findViewById(R.id.like_button)
        private val shareButton: Button = itemView.findViewById(R.id.share_button)
        private val deleteButton: Button = itemView.findViewById(R.id.delete_button)
        private val commentsText: TextView = itemView.findViewById(R.id.comments_text)

        init {
            // Set button labels from strings.xml
            likeButton.text = itemView.context.getString(R.string.post_like)
            shareButton.text = itemView.context.getString(R.string.post_share)
            deleteButton.text = itemView.context.getString(R.string.common_delete)
        }

        fun bind(post: Post) {
            contentText.text = post.content

            // Format comments count using plural resource
            commentsText.text = itemView.context.resources.getQuantityString(
                R.plurals.post_likes_count,
                post.likesCount,
                post.likesCount
            )

            // Alternative: use regular string with format
            // commentsText.text = itemView.context.getString(R.string.post_comments, post.commentsCount)

            likeButton.setOnClickListener {
                onLikeClick(post)
            }

            shareButton.setOnClickListener {
                onShareClick(post)
            }

            deleteButton.setOnClickListener {
                showDeleteConfirmation(post)
            }
        }

        private fun showDeleteConfirmation(post: Post) {
            AlertDialog.Builder(itemView.context)
                .setTitle(itemView.context.getString(R.string.common_delete))
                .setMessage(itemView.context.getString(R.string.post_delete_confirm))
                .setPositiveButton(itemView.context.getString(R.string.common_delete)) { _, _ ->
                    onDeleteClick(post)
                }
                .setNegativeButton(itemView.context.getString(R.string.common_cancel), null)
                .show()
        }
    }

    class PostDiffCallback : DiffUtil.ItemCallback<Post>() {
        override fun areItemsTheSame(oldItem: Post, newItem: Post): Boolean {
            return oldItem.id == newItem.id
        }

        override fun areContentsTheSame(oldItem: Post, newItem: Post): Boolean {
            return oldItem == newItem
        }
    }
}
