/**
 * Test helper: creates a Salesforce Platform user with the
 * Weather_Integration_User permission set. The production code queries and
 * updates Account in user mode, so tests run as a user who has exactly the
 * access the README tells admins to grant (not as a System Administrator).
 */
@IsTest
public class WeatherTestAccess {
  private static final String EMAIL = 'weather.integration.test@example.com';

  public static User createIntegrationUser() {
    // Any Salesforce Platform profile that can edit Accounts (profile names are localized).
    PermissionSet profilePermissions = [
      SELECT ProfileId
      FROM PermissionSet
      WHERE
        IsOwnedByProfile = TRUE
        AND Profile.UserLicense.Name = 'Salesforce Platform'
        AND Id IN (
          SELECT ParentId
          FROM ObjectPermissions
          WHERE SobjectType = 'Account' AND PermissionsEdit = TRUE
        )
      LIMIT 1
    ];
    User u = new User(
      Alias = 'wthrtst',
      Email = EMAIL,
      EmailEncodingKey = 'UTF-8',
      LastName = 'Weather Integration Test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'Europe/Paris',
      ProfileId = profilePermissions.ProfileId,
      Username = 'weather.integration.' +
        System.now().getTime() +
        '@example.com.test'
    );
    insert u;
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Weather_Integration_User'
        LIMIT 1
      ]
      .Id
    );
    return u;
  }

  public static User integrationUser() {
    return [
      SELECT Id
      FROM User
      WHERE Email = :EMAIL AND Alias = 'wthrtst'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
  }
}
