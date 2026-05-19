#!/usr/bin/env python3
"""
AWS Secrets Manager Rotation Lambda Handler

Implements the 4-step rotation protocol required by AWS Secrets Manager:
1. CREATE  — Generate new credential
2. SET     — Apply to target system
3. TEST    — Validate new credential works
4. FINISH  — Promote new credential to current

This is a reference implementation for PostgreSQL.
For other systems (MySQL, RDS, API keys), adapt the SET and TEST steps.

Security Notes:
- Username is assumed to be trusted (internal/configuration-only).
- For untrusted username sources, use psycopg2.sql.Identifier for quoting.
- Secrets Manager state is authoritative; Lambda failures trigger retry.
- Credentials are stored as JSON in Secrets Manager.
"""

import json
import boto3
import psycopg2
from psycopg2 import sql
import os
import logging

# Initialize clients
secrets_client = boto3.client('secretsmanager')
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_secret_dict(secret_id, stage, token=None):
    """
    Retrieve secret value from Secrets Manager.

    Args:
        secret_id: ARN or name of the secret
        stage: "AWSCURRENT", "AWSPENDING", or specific version ID
        token: VersionId for AWSPENDING (required if stage="AWSPENDING")

    Returns:
        Dictionary with secret key-value pairs
    """
    try:
        if stage == "AWSPENDING":
            response = secrets_client.get_secret_value(
                SecretId=secret_id,
                VersionId=token,
                VersionStage=stage
            )
        else:
            response = secrets_client.get_secret_value(
                SecretId=secret_id,
                VersionStage=stage
            )
        return json.loads(response['SecretString'])
    except Exception as e:
        logger.error(f"Error retrieving secret {secret_id} stage {stage}: {str(e)}")
        raise


def set_secret_version_stage(secret_id, version_id, stage):
    """
    Move a version to a new stage (e.g., AWSPENDING → AWSCURRENT).
    """
    try:
        secrets_client.update_secret_version_stage(
            SecretId=secret_id,
            VersionStage=stage,
            MoveToVersionId=version_id,
            RemoveFromVersionId=None  # Auto-remove from old version
        )
        logger.info(f"Moved version {version_id} to stage {stage}")
    except Exception as e:
        logger.error(f"Error updating version stage: {str(e)}")
        raise


def connect_to_database(host, port, user, password, database):
    """
    Establish PostgreSQL connection.
    """
    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=database
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {str(e)}")
        raise


def create_secret(secret_id, client_request_token):
    """
    CREATE step: Generate new database password and store as AWSPENDING version.

    Creates a new secret version with a randomly generated password.
    This version is tagged as AWSPENDING (not yet active).
    """
    logger.info(f"CREATE: Generating new password for secret {secret_id}")

    # Retrieve current secret to get username
    current_secret = get_secret_dict(secret_id, "AWSCURRENT")
    username = current_secret['username']

    # TODO: Use secrets_client.get_random_password() for production:
    # new_password = secrets_client.get_random_password(
    #     PasswordLength=32,
    #     ExcludeCharacters='/@"\\'
    # )['RandomPassword']
    # For now, simple placeholder (replace with actual generation)
    import secrets
    new_password = secrets.token_urlsafe(24)

    # Store new version with AWSPENDING label
    new_secret = {
        'username': username,
        'password': new_password
    }

    try:
        secrets_client.put_secret_value(
            SecretId=secret_id,
            ClientRequestToken=client_request_token,
            SecretString=json.dumps(new_secret),
            VersionStages=['AWSPENDING']
        )
        logger.info(f"CREATE: New version {client_request_token} created with AWSPENDING label")
    except Exception as e:
        logger.error(f"CREATE failed: {str(e)}")
        raise


def set_secret(secret_id, client_request_token):
    """
    SET step: Update database password to the new pending secret.

    Connects to database and changes the user's password to the new value.
    """
    logger.info(f"SET: Applying new password to database")

    # Get current credentials (to connect with)
    current_secret = get_secret_dict(secret_id, "AWSCURRENT")
    # Get pending credentials (new password)
    pending_secret = get_secret_dict(secret_id, "AWSPENDING", client_request_token)

    username = current_secret['username']
    current_password = current_secret['password']
    new_password = pending_secret['password']

    # Database connection parameters (from environment or Terraform)
    host = os.environ.get('DB_HOST', 'localhost')
    port = os.environ.get('DB_PORT', '5432')
    database = os.environ.get('DB_NAME', 'postgres')

    try:
        # Connect with current credentials
        conn = connect_to_database(host, port, username, current_password, database)
        cur = conn.cursor()

        # Update password for the user
        # Note: Username is assumed trusted (from internal Terraform config).
        # For untrusted sources, use: sql.Identifier(username)
        cur.execute(
            f"ALTER USER {username} WITH PASSWORD %s",
            (new_password,)
        )
        conn.commit()
        cur.close()
        conn.close()

        logger.info(f"SET: Password updated for user {username}")

    except Exception as e:
        logger.error(f"SET failed: {str(e)}")
        raise


def test_secret(secret_id, client_request_token):
    """
    TEST step: Verify new password works by connecting to the database.

    This validates that the SET step succeeded before promoting to CURRENT.
    """
    logger.info(f"TEST: Validating new credentials")

    pending_secret = get_secret_dict(secret_id, "AWSPENDING", client_request_token)

    username = pending_secret['username']
    new_password = pending_secret['password']

    host = os.environ.get('DB_HOST', 'localhost')
    port = os.environ.get('DB_PORT', '5432')
    database = os.environ.get('DB_NAME', 'postgres')

    try:
        conn = connect_to_database(host, port, username, new_password, database)
        cur = conn.cursor()
        cur.execute("SELECT version();")
        result = cur.fetchone()
        cur.close()
        conn.close()

        logger.info(f"TEST: Successfully connected with new credentials. Version: {result[0][:50]}")

    except Exception as e:
        logger.error(f"TEST failed: {str(e)}")
        raise


def finish_secret(secret_id, client_request_token):
    """
    FINISH step: Promote AWSPENDING to AWSCURRENT.

    This makes the new password the active version.
    """
    logger.info(f"FINISH: Promoting new version to AWSCURRENT")

    try:
        set_secret_version_stage(secret_id, client_request_token, "AWSCURRENT")
        logger.info(f"FINISH: Rotation complete. New version is now AWSCURRENT")

    except Exception as e:
        logger.error(f"FINISH failed: {str(e)}")
        raise


def lambda_handler(event, context):
    """
    Main Lambda handler.

    AWS Secrets Manager invokes this with:
    {
        "SecretId": "arn:aws:secretsmanager:...",
        "Step": "create|set|test|finish",
        "Token": "version-token-uuid"
    }

    Must implement all 4 steps and handle errors appropriately.
    """
    secret_id = event['SecretId']
    step = event['Step']
    token = event.get('Token', '')

    logger.info(f"Rotation Lambda invoked: secret={secret_id}, step={step}, token={token}")

    try:
        if step == "create":
            create_secret(secret_id, token)

        elif step == "set":
            set_secret(secret_id, token)

        elif step == "test":
            test_secret(secret_id, token)

        elif step == "finish":
            finish_secret(secret_id, token)

        else:
            raise ValueError(f"Invalid step: {step}. Must be create|set|test|finish")

        logger.info(f"Step '{step}' completed successfully")
        return {
            'statusCode': 200,
            'body': json.dumps(f"Rotation step '{step}' completed successfully")
        }

    except Exception as e:
        logger.error(f"Rotation failed at step '{step}': {str(e)}")
        # AWS will retry failed rotations automatically
        raise


# TODO (Production Hardening):
# - Add CloudWatch metrics for rotation success/failure
# - Add SNS notifications on rotation events
# - Add retry logic with exponential backoff
# - Add support for multiple database types (MySQL, Oracle, etc.)
# - Add certificate validation for RDS connections
# - Add VPC Endpoint support for Secrets Manager
# - Add comprehensive error classification
# - Add secret rotation audit logging
