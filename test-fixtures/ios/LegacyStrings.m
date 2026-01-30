//
//  LegacyStrings.m
//  MyApp
//
//  Objective-C examples for localization patterns.
//  These patterns should also be detected by the searcher.
//

#import "LegacyStrings.h"

@implementation LegacyStrings

- (void)setupUI {
    // Standard NSLocalizedString
    NSString *title = NSLocalizedString(@"objc.screen.title", @"Screen title");

    // With nil comment
    NSString *subtitle = NSLocalizedString(@"objc.screen.subtitle", nil);

    // Multi-line NSLocalizedString
    NSString *description = NSLocalizedString(
        @"objc.screen.description",
        @"Long description text"
    );

    NSLog(@"%@ %@ %@", title, subtitle, description);
}

- (void)configureCell:(UITableViewCell *)cell {
    cell.textLabel.text = NSLocalizedString(@"objc.cell.title", @"Cell title");
    cell.detailTextLabel.text = NSLocalizedString(@"objc.cell.detail", @"Cell detail");

    // Accessibility
    cell.accessibilityLabel = NSLocalizedString(@"objc.cell.accessibility", @"Full cell description");
}

- (void)showAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"objc.alert.title", @"Alert title")
        message:NSLocalizedString(@"objc.alert.message", @"Alert message")
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"objc.alert.cancel", @"Cancel button")
        style:UIAlertActionStyleCancel
        handler:nil];

    UIAlertAction *confirmAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"objc.alert.confirm", @"Confirm button")
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [self performAction];
        }];

    [alert addAction:cancelAction];
    [alert addAction:confirmAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)formatStrings {
    // NSLocalizedString with format
    NSString *format = NSLocalizedString(@"objc.format.count", @"Count format: %d items");
    NSString *result = [NSString stringWithFormat:format, 5];

    // Plural handling
    NSString *pluralFormat = NSLocalizedString(@"objc.format.plural", @"Plural format");
    NSLog(@"%@ %@", result, pluralFormat);
}

// MARK: - Table identifiers (should work with NSLocalizedStringFromTable)

- (void)tableStrings {
    // NSLocalizedStringFromTable - loads from specific .strings file
    NSString *custom = NSLocalizedStringFromTable(@"objc.custom.key", @"CustomStrings", @"Custom table string");

    // NSLocalizedStringFromTableInBundle - with bundle
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundled = NSLocalizedStringFromTableInBundle(@"objc.bundle.key", @"Strings", bundle, @"Bundled string");

    NSLog(@"%@ %@", custom, bundled);
}

- (void)performAction {
    // Implementation
}

@end
