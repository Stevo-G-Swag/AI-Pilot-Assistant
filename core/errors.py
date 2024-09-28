class APIError(Exception):
    """Custom exception class for API errors."""
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message