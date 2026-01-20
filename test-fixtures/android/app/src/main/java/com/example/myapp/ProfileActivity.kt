package com.example.myapp

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.progressindicator.CircularProgressIndicator

class ProfileActivity : AppCompatActivity() {

    private lateinit var profileImage: ImageView
    private lateinit var changePhotoButton: Button
    private lateinit var nameEditText: EditText
    private lateinit var saveButton: Button
    private lateinit var loadingIndicator: CircularProgressIndicator

    private val pickImageLauncher = registerForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri ->
        uri?.let { profileImage.setImageURI(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_profile)

        // Set title from strings.xml
        title = getString(R.string.profile_edit)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        setupViews()
    }

    private fun setupViews() {
        profileImage = findViewById(R.id.profile_image)
        changePhotoButton = findViewById(R.id.change_photo_button)
        nameEditText = findViewById(R.id.name_edit_text)
        saveButton = findViewById(R.id.save_button)
        loadingIndicator = findViewById(R.id.loading_indicator)

        // Set button text from strings.xml
        changePhotoButton.text = getString(R.string.profile_photo_change)
        saveButton.text = getString(R.string.common_save)

        // Set placeholder text
        nameEditText.hint = getString(R.string.profile_name_placeholder)

        changePhotoButton.setOnClickListener {
            pickImageLauncher.launch("image/*")
        }

        saveButton.setOnClickListener {
            saveProfile()
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.profile_menu, menu)
        menu.findItem(R.id.action_cancel)?.title = getString(R.string.common_cancel)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home, R.id.action_cancel -> {
                finish()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun saveProfile() {
        val name = nameEditText.text.toString()

        if (name.isBlank()) {
            nameEditText.error = getString(R.string.error_not_found)
            return
        }

        // Show loading indicator
        showLoading(true)
        Toast.makeText(this, getString(R.string.common_loading), Toast.LENGTH_SHORT).show()

        // Simulate network call
        saveButton.postDelayed({
            showLoading(false)
            onSaveResult(Result.success(Unit))
        }, 2000)
    }

    private fun showLoading(show: Boolean) {
        loadingIndicator.visibility = if (show) android.view.View.VISIBLE else android.view.View.GONE
        saveButton.isEnabled = !show
    }

    private fun onSaveResult(result: Result<Unit>) {
        result.fold(
            onSuccess = {
                Toast.makeText(this, getString(R.string.common_done), Toast.LENGTH_SHORT).show()
                finish()
            },
            onFailure = { error ->
                val message = when (error) {
                    is NetworkException -> getString(R.string.error_network)
                    is UnauthorizedException -> getString(R.string.error_unauthorized)
                    else -> getString(R.string.error_not_found)
                }

                MaterialAlertDialogBuilder(this)
                    .setMessage(message)
                    .setPositiveButton(getString(R.string.common_done), null)
                    .show()
            }
        )
    }
}

class NetworkException : Exception()
class UnauthorizedException : Exception()
