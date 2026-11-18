"""
Custom exception classes for Nexora VPN CLI with associated exit codes.
"""

from .constants import (
    EXIT_GENERAL_ERROR,
    EXIT_INVALID_INPUT,
    EXIT_AUTH_FAILED,
    EXIT_CONNECTION_ERROR,
    EXIT_INSUFFICIENT_PRIVILEGES,
    EXIT_SERVICE_UNAVAILABLE,
)

class NexoraException(Exception):
    def __init__(self, message: str, exit_code: int = EXIT_GENERAL_ERROR):
        super().__init__(message)
        self.message = message
        self.exit_code = exit_code

class InvalidInputError(NexoraException):
    def __init__(self, message: str):
        super().__init__(message, EXIT_INVALID_INPUT)

class AuthError(NexoraException):
    def __init__(self, message: str):
        super().__init__(message, EXIT_AUTH_FAILED)

class ConnectionError(NexoraException):
    def __init__(self, message: str):
        super().__init__(message, EXIT_CONNECTION_ERROR)

class PermissionError(NexoraException):
    def __init__(self, message: str):
        super().__init__(message, EXIT_INSUFFICIENT_PRIVILEGES)

class ServiceUnavailableError(NexoraException):
    def __init__(self, message: str):
        super().__init__(message, EXIT_SERVICE_UNAVAILABLE)
