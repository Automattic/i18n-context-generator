package com.example.myapp

import android.os.Bundle
import android.view.MenuItem
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat

class SettingsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.settings_activity)

        // Set the title from strings.xml
        title = getString(R.string.settings_title)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        if (savedInstanceState == null) {
            supportFragmentManager
                .beginTransaction()
                .replace(R.id.settings, SettingsFragment())
                .commit()
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId == android.R.id.home) {
            onBackPressed()
            return true
        }
        return super.onOptionsItemSelected(item)
    }

    class SettingsFragment : PreferenceFragmentCompat() {

        override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
            setPreferencesFromResource(R.xml.preferences, rootKey)

            // Set up notifications preference
            findPreference<Preference>("notifications")?.apply {
                title = getString(R.string.settings_notifications)
                summary = getString(R.string.settings_notifications_description)
            }

            // Set up privacy preference
            findPreference<Preference>("privacy")?.apply {
                title = getString(R.string.settings_privacy)
            }

            // Set up logout preference
            findPreference<Preference>("logout")?.apply {
                title = getString(R.string.settings_logout)
                setOnPreferenceClickListener {
                    showLogoutConfirmation()
                    true
                }
            }
        }

        private fun showLogoutConfirmation() {
            AlertDialog.Builder(requireContext())
                .setTitle(getString(R.string.settings_logout))
                .setMessage(getString(R.string.settings_logout_confirm))
                .setPositiveButton(getString(R.string.settings_logout)) { _, _ ->
                    performLogout()
                }
                .setNegativeButton(getString(R.string.common_cancel), null)
                .show()
        }

        private fun performLogout() {
            // Logout implementation
            activity?.finish()
        }
    }
}
