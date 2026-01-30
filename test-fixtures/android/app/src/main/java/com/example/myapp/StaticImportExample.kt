package com.example.myapp

import android.os.Bundle
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

// Static import of R.string - allows using string.key_name pattern
import com.example.myapp.R.string

/**
 * Example demonstrating static import pattern for string resources.
 * When using `import R.string`, you can reference strings as `string.key_name`
 * instead of `R.string.key_name`.
 */
class StaticImportActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        setupViews()
    }

    private fun setupViews() {
        // Using static import pattern: string.key_name
        title = getString(string.static_import_title)

        // Multiple uses of static import pattern
        val welcomeText = findViewById<TextView>(R.id.welcome_text)
        welcomeText.text = getString(string.static_import_welcome)

        // In Toast
        Toast.makeText(
            this,
            getString(string.static_import_toast),
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun showMessage() {
        // Direct string.key reference (without getString wrapper)
        val messageResId = string.static_import_message

        // Using with resources
        val message = resources.getString(messageResId)

        // In conditional
        val errorMessage = if (hasError()) {
            getString(string.static_import_error)
        } else {
            getString(string.static_import_success)
        }

        println(message + errorMessage)
    }

    private fun formattedStrings() {
        // Static import with format
        val formatted = getString(string.static_import_format, 10)

        // In string concatenation context
        val combined = getString(string.static_import_prefix) +
            ": " +
            getString(string.static_import_suffix)

        println(formatted + combined)
    }

    private fun hasError(): Boolean = false
}

// Also test in a different class in same file
class AnotherStaticImportExample {
    fun example(activity: AppCompatActivity) {
        // Static import should work across classes in same file
        val text = activity.getString(string.static_import_another)
        println(text)
    }
}
