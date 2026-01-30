package com.example.myapp

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

/**
 * Jetpack Compose examples using stringResource() pattern.
 * This is the modern way to use localized strings in Compose UI.
 */
@Composable
fun ComposeHomeScreen(
    onNavigateToSettings: () -> Unit,
    onNavigateToProfile: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Basic stringResource usage
        Text(
            text = stringResource(R.string.compose_welcome_title),
            style = MaterialTheme.typography.headlineMedium
        )

        Spacer(modifier = Modifier.height(8.dp))

        // stringResource in Text
        Text(
            text = stringResource(R.string.compose_welcome_subtitle),
            style = MaterialTheme.typography.bodyLarge
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Button with stringResource
        Button(
            onClick = onNavigateToSettings
        ) {
            Text(stringResource(R.string.compose_button_settings))
        }

        Spacer(modifier = Modifier.height(8.dp))

        // OutlinedButton with stringResource
        OutlinedButton(
            onClick = onNavigateToProfile
        ) {
            Text(stringResource(R.string.compose_button_profile))
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Card with multiple localized strings
        Card(
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = stringResource(R.string.compose_card_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.compose_card_description),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
fun ComposeFormScreen() {
    var text by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // TextField with stringResource for label and placeholder
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            label = { Text(stringResource(R.string.compose_input_label)) },
            placeholder = { Text(stringResource(R.string.compose_input_placeholder)) },
            modifier = Modifier.fillMaxWidth()
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Multi-line stringResource call
        Text(
            text = stringResource(
                R.string.compose_multiline_example
            ),
            style = MaterialTheme.typography.bodyMedium
        )

        Spacer(modifier = Modifier.height(16.dp))

        // stringResource with format arguments
        Text(
            text = stringResource(R.string.compose_format_example, 5, "items"),
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
fun ComposeDialogExample(
    onDismiss: () -> Unit,
    onConfirm: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(stringResource(R.string.compose_dialog_title))
        },
        text = {
            Text(stringResource(R.string.compose_dialog_message))
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(stringResource(R.string.compose_dialog_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.compose_dialog_cancel))
            }
        }
    )
}

// Composable with extracted string values
@Composable
fun ComposeExtractedStrings() {
    // Extracting to local val for reuse
    val title = stringResource(R.string.compose_extracted_title)
    val description = stringResource(R.string.compose_extracted_description)

    Column {
        Text(title)
        Text(description)
        // Reusing the same string
        Text(title)
    }
}
